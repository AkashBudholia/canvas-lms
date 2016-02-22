#
# Copyright (C) 2013 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper.rb')

describe CourseLinkValidator do

  it "should validate all the links" do
    CourseLinkValidator.any_instance.stubs(:reachable_url?).returns(false).once # don't actually ping the links for the specs

    course
    attachment_model

    bad_url = "http://www.notarealsitebutitdoesntmattercauseimstubbingitanwyay.com"
    bad_url2 = "/courses/#{@course.id}/file_contents/baaaad"
    html = %{
      <a href="#{bad_url}">Bad absolute link</a>
      <img src="#{bad_url2}">Bad file link</a>
      <img src="/courses/#{@course.id}/file_contents/#{CGI.escape(@attachment.full_display_path)}">Ok file link</a>
      <a href="/courses/#{@course.id}/quizzes">Ok other link</a>
    }

    @course.syllabus_body = html
    @course.save!

    bank = @course.assessment_question_banks.create!(:title => 'bank')
    aq = bank.assessment_questions.create!(:question_data => {'name' => 'test question',
      'question_text' => html, 'answers' => [{'id' => 1}, {'id' => 2}]})

    assmnt = @course.assignments.create!(:title => 'assignment', :description => html)
    event = @course.calendar_events.create!(:title => "event", :description => html)
    topic = @course.discussion_topics.create!(:title => "discussion title", :message => html)
    mod = @course.context_modules.create!(:name => "some module")
    tag = mod.add_item(:type => 'external_url', :url => bad_url, :title => 'pls view')
    page = @course.wiki.wiki_pages.create!(:title => "wiki", :body => html)
    quiz = @course.quizzes.create!(:title => 'quiz1', :description => html)

    qq = quiz.quiz_questions.create!(:question_data => aq.question_data)

    CourseLinkValidator.queue_course(@course)
    run_jobs

    issues = CourseLinkValidator.current_progress(@course).results[:issues]
    issues.each do |issue|
      expect(issue[:invalid_links]).to include({:reason => :unreachable, :url => bad_url})
      next if issue[:type] == :module_item
      expect(issue[:invalid_links]).to include({:reason => :missing_file, :url => bad_url2})
    end

    type_names = {
      :syllabus => 'Course Syllabus',
      :assessment_question => aq.question_data[:question_name],
      :quiz_question => qq.question_data[:question_name],
      :assignment => assmnt.title,
      :calendar_event => event.title,
      :discussion_topic => topic.title,
      :module_item => tag.title,
      :quiz => quiz.title,
      :wiki_page => page.title
    }
    type_names.each do |type, name|
      expect(issues.select{|issue| issue[:type] == type}.count).to eq(1)
      expect(issues.detect{|issue| issue[:type] == type}[:name]).to eq(name)
    end

  end

  it "should not run on assessment questions in deleted banks" do
    CourseLinkValidator.any_instance.stubs(:reachable_url?).returns(false) # don't actually ping the links for the specs
    html = %{<a href='http://www.notarealsitebutitdoesntmattercauseimstubbingitanwyay.com'>linky</a>}

    course
    bank = @course.assessment_question_banks.create!(:title => 'bank')
    aq = bank.assessment_questions.create!(:question_data => {'name' => 'test question',
      'question_text' => html, 'answers' => [{'id' => 1}, {'id' => 2}]})

    CourseLinkValidator.queue_course(@course)
    run_jobs

    issues = CourseLinkValidator.current_progress(@course).results[:issues]
    expect(issues.count).to eq 1

    bank.destroy

    CourseLinkValidator.queue_course(@course)
    run_jobs

    issues = CourseLinkValidator.current_progress(@course).results[:issues]
    expect(issues).to be_empty
  end

  it "should not care if it can reach it" do
    CourseLinkValidator.any_instance.stubs(:reachable_url?).returns(true)

    course
    topic = @course.discussion_topics.create!(:message => %{<a href="http://www.www.www">pretend this is real</a>}, :title => "title")

    CourseLinkValidator.queue_course(@course)
    run_jobs

    issues = CourseLinkValidator.current_progress(@course).results[:issues]
    expect(issues).to be_empty
  end

  it "should check for deleted/unpublished objects" do
    course
    active = @course.assignments.create!(:title => "blah")
    unpublished = @course.assignments.create!(:title => "blah")
    unpublished.unpublish!
    deleted = @course.assignments.create!(:title => "blah")
    deleted.destroy

    active_link = "/courses/#{@course.id}/assignments/#{active.id}"
    unpublished_link = "/courses/#{@course.id}/assignments/#{unpublished.id}"
    deleted_link = "/courses/#{@course.id}/assignments/#{deleted.id}"

    message = %{
      <a href='#{active_link}'>link</a>
      <a href='#{unpublished_link}'>link</a>
      <a href='#{deleted_link}'>link</a>
    }
    @course.syllabus_body = message
    @course.save!

    CourseLinkValidator.queue_course(@course)
    run_jobs

    links = CourseLinkValidator.current_progress(@course).results[:issues].first[:invalid_links].map{|l| l[:url]}
    expect(links).to match_array [unpublished_link, deleted_link]
  end

  it "should work with absolute links to local objects" do
    course
    deleted = @course.assignments.create!(:title => "blah")
    deleted.destroy

    deleted_link = "http://#{HostUrl.default_host}/courses/#{@course.id}/assignments/#{deleted.id}"

    message = "<a href='#{deleted_link}'>link</a>"
    @course.syllabus_body = message
    @course.save!

    CourseLinkValidator.queue_course(@course)
    run_jobs

    links = CourseLinkValidator.current_progress(@course).results[:issues].first[:invalid_links].map{|l| l[:url]}
    expect(links).to match_array [deleted_link]
  end

  it "should find links to other courses" do
    other_course = course
    course

    link = "http://#{HostUrl.default_host}/courses/#{other_course.id}/assignments"

    message = "<a href='#{link}'>link</a>"
    @course.syllabus_body = message
    @course.save!

    CourseLinkValidator.queue_course(@course)
    run_jobs

    links = CourseLinkValidator.current_progress(@course).results[:issues].first[:invalid_links]
    expect(links.count).to eq 1
    expect(links.first[:url]).to eq link
    expect(links.first[:reason]).to eq :course_mismatch
  end

  it "should find links to wiki pages" do
    course
    active = @course.wiki.wiki_pages.create!(:title => "active and stuff")
    unpublished = @course.wiki.wiki_pages.create!(:title => "unpub")
    unpublished.unpublish!
    deleted = @course.wiki.wiki_pages.create!(:title => "baleeted")
    deleted.destroy

    active_link = "/courses/#{@course.id}/pages/#{active.url}"
    unpublished_link = "/courses/#{@course.id}/pages/#{unpublished.url}"
    deleted_link = "/courses/#{@course.id}/pages/#{deleted.url}"

    message = %{
      <a href='#{active_link}'>link</a>
      <a href='#{active_link}#achor'>link</a>
      <a href='#{active_link}?query_param'>link</a>
      <a href='#{unpublished_link}'>link</a>
      <a href='#{deleted_link}'>link</a>
    }
    @course.syllabus_body = message
    @course.save!

    CourseLinkValidator.queue_course(@course)
    run_jobs

    links = CourseLinkValidator.current_progress(@course).results[:issues].first[:invalid_links].map{|l| l[:url]}
    expect(links).to match_array [unpublished_link, deleted_link]
  end

  it "should identify typo'd canvas links" do
    course
    invalid_link1 = "/cupbopourses"
    invalid_link2 = "http://#{HostUrl.default_host}/courses/#{@course.id}/pon3s"

    message = %{
      <a href='/courses'>link</a>
      <a href='/courses/#{@course.id}/assignments/'>link</a>
      <a href='#{invalid_link1}'>link</a>
      <a href='#{invalid_link2}'>link</a>
    }
    @course.syllabus_body = message
    @course.save!

    CourseLinkValidator.queue_course(@course)
    run_jobs

    links = CourseLinkValidator.current_progress(@course).results[:issues].first[:invalid_links].map{|l| l[:url]}
    expect(links).to match_array [invalid_link1, invalid_link2]
  end

  it "should not flag valid replaced attachments" do
    course
    att1 = attachment_with_context(@course, :display_name => "name")
    att2 = attachment_with_context(@course)

    att2.display_name = "name"
    att2.handle_duplicates(:overwrite)
    att1.reload
    expect(att1.replacement_attachment).to eq att2

    link = "/courses/#{@course.id}/files/#{att1.id}/download" # should still work because it uses att2 as a fallback
    message = %{
      <a href='#{link}'>link</a>
    }
    @course.syllabus_body = message
    @course.save!

    CourseLinkValidator.queue_course(@course)
    run_jobs

    issues = CourseLinkValidator.current_progress(@course).results[:issues]
    expect(issues).to be_empty

    att2.destroy # shouldn't work anymore

    CourseLinkValidator.queue_course(@course)
    run_jobs

    links = CourseLinkValidator.current_progress(@course).results[:issues].first[:invalid_links].map{|l| l[:url]}
    expect(links).to match_array [link]
  end

  it "should not flag links to public paths" do
    course
    @course.syllabus_body = %{<a href='/images/avatar-50.png'>link</a>}
    @course.save!

    CourseLinkValidator.queue_course(@course)
    run_jobs

    issues = CourseLinkValidator.current_progress(@course).results[:issues]
    expect(issues).to be_empty
  end

  it "should flag sneaky links" do
    course
    @course.syllabus_body = %{<a href='/../app/models/user.rb'>link</a>}
    @course.save!

    CourseLinkValidator.queue_course(@course)
    run_jobs

    issues = CourseLinkValidator.current_progress(@course).results[:issues]
    expect(issues.count).to eq 1
  end
end

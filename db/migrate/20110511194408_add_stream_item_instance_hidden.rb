#
# Copyright (C) 2011 - present Instructure, Inc.
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

class AddStreamItemInstanceHidden < ActiveRecord::Migration[4.2]
  tag :predeploy

  def self.up
    add_column :stream_item_instances, :hidden, :boolean, :default => false, :null => false

    add_index :stream_item_instances, %w(user_id hidden id stream_item_id), :name => "index_stream_item_instances_global"
    add_index :stream_item_instances, %w(user_id context_code hidden id stream_item_id), :name => "index_stream_item_instances_context"
  end

  def self.down
    remove_column :stream_item_instances, :hidden
  end
end
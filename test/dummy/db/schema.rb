# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20130924162315) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

# Could not dump table "catalog_versions" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "catalogs" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "cms_attachment_versions" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "cms_attachments" because of following FrozenError
#   can't modify frozen String: "false"

  create_table "cms_categories", force: :cascade do |t|
    t.integer  "category_type_id"
    t.integer  "parent_id"
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "cms_category_types", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "cms_connectors", force: :cascade do |t|
    t.integer  "page_id"
    t.integer  "page_version"
    t.integer  "connectable_id"
    t.string   "connectable_type"
    t.integer  "connectable_version"
    t.string   "container"
    t.integer  "position"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "cms_connectors", ["connectable_type"], name: "index_cms_connectors_on_connectable_type", using: :btree
  add_index "cms_connectors", ["connectable_version"], name: "index_cms_connectors_on_connectable_version", using: :btree
  add_index "cms_connectors", ["page_id"], name: "index_cms_connectors_on_page_id", using: :btree
  add_index "cms_connectors", ["page_version"], name: "index_cms_connectors_on_page_version", using: :btree

# Could not dump table "cms_dynamic_view_versions" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "cms_dynamic_views" because of following FrozenError
#   can't modify frozen String: "false"

  create_table "cms_email_messages", force: :cascade do |t|
    t.string   "sender"
    t.text     "recipients"
    t.text     "subject"
    t.text     "cc"
    t.text     "bcc"
    t.text     "body"
    t.string   "content_type"
    t.datetime "delivered_at"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

# Could not dump table "cms_file_block_versions" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "cms_file_blocks" because of following FrozenError
#   can't modify frozen String: "false"

  create_table "cms_form_entries", force: :cascade do |t|
    t.text     "data_columns"
    t.integer  "form_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "cms_form_fields", force: :cascade do |t|
    t.integer  "form_id"
    t.string   "label"
    t.string   "name"
    t.string   "field_type"
    t.boolean  "required"
    t.integer  "position"
    t.text     "instructions"
    t.text     "default_value"
    t.text     "choices"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "cms_form_fields", ["form_id", "name"], name: "index_cms_form_fields_on_form_id_and_name", unique: true, using: :btree

# Could not dump table "cms_form_versions" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "cms_forms" because of following FrozenError
#   can't modify frozen String: "false"

  create_table "cms_group_permissions", force: :cascade do |t|
    t.integer "group_id"
    t.integer "permission_id"
  end

  add_index "cms_group_permissions", ["group_id", "permission_id"], name: "index_cms_group_permissions_on_group_id_and_permission_id", using: :btree
  add_index "cms_group_permissions", ["group_id"], name: "index_cms_group_permissions_on_group_id", using: :btree
  add_index "cms_group_permissions", ["permission_id"], name: "index_cms_group_permissions_on_permission_id", using: :btree

  create_table "cms_group_sections", force: :cascade do |t|
    t.integer "group_id"
    t.integer "section_id"
  end

  add_index "cms_group_sections", ["group_id"], name: "index_cms_group_sections_on_group_id", using: :btree
  add_index "cms_group_sections", ["section_id"], name: "index_cms_group_sections_on_section_id", using: :btree

  create_table "cms_group_type_permissions", force: :cascade do |t|
    t.integer "group_type_id"
    t.integer "permission_id"
  end

# Could not dump table "cms_group_types" because of following FrozenError
#   can't modify frozen String: "false"

  create_table "cms_groups", force: :cascade do |t|
    t.string   "name"
    t.string   "code"
    t.integer  "group_type_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "cms_groups", ["code"], name: "index_cms_groups_on_code", using: :btree
  add_index "cms_groups", ["group_type_id"], name: "index_cms_groups_on_group_type_id", using: :btree

# Could not dump table "cms_html_block_versions" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "cms_html_blocks" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "cms_link_versions" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "cms_links" because of following FrozenError
#   can't modify frozen String: "false"

  create_table "cms_page_route_options", force: :cascade do |t|
    t.integer  "page_route_id"
    t.string   "type"
    t.string   "name"
    t.string   "value"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "cms_page_routes", force: :cascade do |t|
    t.string   "name"
    t.string   "pattern"
    t.integer  "page_id"
    t.text     "code"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

# Could not dump table "cms_page_versions" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "cms_pages" because of following FrozenError
#   can't modify frozen String: "false"

  create_table "cms_permissions", force: :cascade do |t|
    t.string   "name"
    t.string   "full_name"
    t.string   "description"
    t.string   "for_module"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "cms_portlet_attributes", force: :cascade do |t|
    t.integer "portlet_id"
    t.string  "name"
    t.text    "value"
  end

  add_index "cms_portlet_attributes", ["portlet_id"], name: "index_cms_portlet_attributes_on_portlet_id", using: :btree

# Could not dump table "cms_portlets" because of following FrozenError
#   can't modify frozen String: "false"

  create_table "cms_redirects", force: :cascade do |t|
    t.string   "from_path"
    t.string   "to_path"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "cms_redirects", ["from_path"], name: "index_cms_redirects_on_from_path", using: :btree

  create_table "cms_section_nodes", force: :cascade do |t|
    t.string   "node_type"
    t.integer  "node_id"
    t.integer  "position"
    t.string   "ancestry"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "slug"
  end

  add_index "cms_section_nodes", ["ancestry"], name: "index_cms_section_nodes_on_ancestry", using: :btree
  add_index "cms_section_nodes", ["node_type"], name: "index_cms_section_nodes_on_node_type", using: :btree

# Could not dump table "cms_sections" because of following FrozenError
#   can't modify frozen String: "false"

  create_table "cms_sites", force: :cascade do |t|
    t.string   "name"
    t.string   "domain"
    t.boolean  "the_default"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "cms_taggings", force: :cascade do |t|
    t.integer  "tag_id"
    t.integer  "taggable_id"
    t.string   "taggable_type"
    t.integer  "taggable_version"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "cms_tags", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "cms_tasks", force: :cascade do |t|
    t.integer  "assigned_by_id"
    t.integer  "assigned_to_id"
    t.integer  "page_id"
    t.text     "comment"
    t.date     "due_date"
    t.datetime "completed_at"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "cms_tasks", ["assigned_to_id"], name: "index_cms_tasks_on_assigned_to_id", using: :btree
  add_index "cms_tasks", ["completed_at"], name: "index_cms_tasks_on_completed_at", using: :btree
  add_index "cms_tasks", ["page_id"], name: "index_cms_tasks_on_page_id", using: :btree

  create_table "cms_user_group_memberships", force: :cascade do |t|
    t.integer "user_id"
    t.integer "group_id"
  end

  add_index "cms_user_group_memberships", ["group_id"], name: "index_cms_user_group_memberships_on_group_id", using: :btree
  add_index "cms_user_group_memberships", ["user_id"], name: "index_cms_user_group_memberships_on_user_id", using: :btree

  create_table "cms_users", force: :cascade do |t|
    t.string   "login",                  limit: 40
    t.string   "first_name",             limit: 40
    t.string   "last_name",              limit: 40
    t.string   "email",                  limit: 40
    t.string   "salt",                   limit: 40
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "expires_at"
    t.datetime "remember_created_at"
    t.string   "reset_password_token"
    t.string   "encrypted_password",                default: "",          null: false
    t.datetime "reset_password_sent_at"
    t.string   "type",                              default: "Cms::User"
    t.string   "source"
    t.text     "external_data"
  end

  add_index "cms_users", ["email"], name: "index_cms_users_on_email", unique: true, using: :btree
  add_index "cms_users", ["expires_at"], name: "index_cms_users_on_expires_at", using: :btree
  add_index "cms_users", ["login"], name: "index_cms_users_on_login", unique: true, using: :btree
  add_index "cms_users", ["reset_password_token"], name: "index_cms_users_on_reset_password_token", unique: true, using: :btree

# Could not dump table "deprecated_input_versions" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "deprecated_inputs" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "product_versions" because of following FrozenError
#   can't modify frozen String: "false"

# Could not dump table "products" because of following FrozenError
#   can't modify frozen String: "false"

end

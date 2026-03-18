# frozen_string_literal: true

require "yaml"

def make_user_yml(search_setting:, search_result:)
  object = {
    "name" => search_setting.name.strip,
    "bio" => search_setting.bio.strip,
    "avatar" => search_setting.avatar.strip,
  }
  YAML.dump(object)
end
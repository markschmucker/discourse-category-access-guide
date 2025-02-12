# frozen_string_literal: true

# name: discourse-category-access-guide
# about: TODO
# meta_topic_id: TODO
# version: 0.0.1
# authors: Discourse
# url: TODO
# required_version: 2.7.0

enabled_site_setting :discourse_category_access_guide_enabled

module ::DiscourseCategoryAccessGuide
  PLUGIN_NAME = "discourse-category-access-guide"
end

require_relative "lib/discourse_category_access_guide/engine"

after_initialize do
  # Code which should run after Rails has finished booting
end

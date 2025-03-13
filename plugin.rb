# frozen_string_literal: true

# name: discourse-category-access-guide
# about: A Discourse plugin that displays category-specific access messages, guiding users on how to gain entry based on predefined access rules.
# version: 0.1
# authors: Jahan Gagan
# url: https://github.com/jahan-ggn/discourse-category-access-guide

enabled_site_setting :discourse_category_access_guide_enabled

after_initialize do
  module ::DiscourseCategoryAccessGuide
    class CustomInvalidAccess < StandardError
      attr_reader :custom_message, :custom_message_params

      def initialize(msg = nil, opts = {})
        super(msg)
        @custom_message = opts[:custom_message]
        @custom_message_params = opts[:custom_message_params]
      end
    end
  end

  # Helper module to handle custom invalid access across multiple controllers
  module ::AccessGuideHelper
    def handle_custom_invalid_access(e)
      opts = { custom_message: e.custom_message, custom_message_params: e.custom_message_params }
      render_custom_access_guide_page(403, opts)
    end

    def render_custom_access_guide_page(status_code, opts = {})
      show_json_errors = request.format.json? || request.xhr? || params[:format] == "json"
      title = I18n.t("access_denied")

      if show_json_errors
        render_json_error(title, type: :custom_invalid_access, status: status_code)
      else
        @topics_partial = nil
        @hide_search = true
        @page_title = title
        @title = I18n.t(opts[:custom_message], opts[:custom_message_params] || {}).html_safe
        @current_user =
          begin
            current_user
          rescue StandardError
            nil
          end

        render status: status_code,
               layout: "no_ember",
               formats: [:html],
               template: "/exceptions/not_found"
      end
    end
  end

  module ::GuardianCategoryAccessExtension
    def can_see_category?(category)
      default_permission = super(category)

      return default_permission if category.blank? || default_permission
      return default_permission unless SiteSetting.discourse_category_access_guide_enabled

      category_access_map = JSON.parse(SiteSetting.category_access_map || "{}")

      restricted_category_id = nil
      topic_guide_url = nil

      # Check if the accessed category is restricted
      if category_access_map[category.id.to_s].present?
        restricted_category_id = category.id
        topic_guide_url = category_access_map[category.id.to_s]
      end

      # Check if its parent category is restricted
      if category.parent_category_id.present? &&
           category_access_map[category.parent_category_id.to_s].present?
        restricted_category_id = category.parent_category_id
        topic_guide_url = category_access_map[category.parent_category_id.to_s]
      end

      # If either category or its parent is restricted, deny access
      if restricted_category_id
        raise ::DiscourseCategoryAccessGuide::CustomInvalidAccess.new(
                "category_access_error",
                custom_message: "error_message",
                custom_message_params: {
                  url: topic_guide_url,
                },
              )
      end

      default_permission
    end
  end

  Guardian.prepend(GuardianCategoryAccessExtension)

  module ::TopicsControllerCAGExtension
    include ::AccessGuideHelper

    def self.prepended(base)
      base.rescue_from ::DiscourseCategoryAccessGuide::CustomInvalidAccess,
                       with: :handle_custom_invalid_access
    end

    def show
      super
    rescue Discourse::InvalidAccess
      handle_invalid_access
    end

    private

    def handle_invalid_access
      topic = Topic.find_by(id: params[:topic_id].to_i) or raise Discourse::InvalidAccess
      category_id = topic.category_id
      category = Category.find_by(id: category_id)

      category_access_map = JSON.parse(SiteSetting.category_access_map || "{}")
      puts "F ----> #{category_access_map}"
      restricted_category_id = nil
      topic_guide_url = nil

      # Check if the accessed category is restricted
      if category_access_map[category_id.to_s].present?
        restricted_category_id = category_id
        topic_guide_url = category_access_map[category_id.to_s]
      end

      # Check if its parent category is restricted
      if category&.parent_category_id.present? &&
           category_access_map[category.parent_category_id.to_s].present?
        restricted_category_id = category.parent_category_id
        topic_guide_url = category_access_map[category.parent_category_id.to_s]
      end

      # If either category or its parent is restricted, deny access
      if restricted_category_id
        raise ::DiscourseCategoryAccessGuide::CustomInvalidAccess.new(
                "topic_access_error",
                custom_message: "error_message",
                custom_message_params: {
                  url: topic_guide_url,
                },
              )
      end

      raise Discourse::InvalidAccess
    end
  end

  module ::ListControllerCAGExtension
    include ::AccessGuideHelper

    def self.prepended(base)
      base.rescue_from ::DiscourseCategoryAccessGuide::CustomInvalidAccess,
                       with: :handle_custom_invalid_access
    end
  end

  ::TopicsController.prepend(TopicsControllerCAGExtension)
  ::ListController.prepend(ListControllerCAGExtension)
end

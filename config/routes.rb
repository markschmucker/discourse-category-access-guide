# frozen_string_literal: true

# frozen_string_literal: true

DiscourseCategoryAccessGuide::Engine.routes.draw { get "/examples" => "examples#index" }

Discourse::Application.routes.draw do
  mount ::DiscourseCategoryAccessGuide::Engine, at: "discourse-category-access-guide"
end

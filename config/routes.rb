# frozen_string_literal: true

DiscourseCategoryAccessGuide::Engine.routes.draw do
  get "/examples" => "examples#index"
  # define routes here
end

Discourse::Application.routes.draw { mount ::DiscourseCategoryAccessGuide::Engine, at: "discourse-category-access-guide" }

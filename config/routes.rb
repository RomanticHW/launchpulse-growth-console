Rails.application.routes.draw do
  root "dashboard#index"
  get "favicon.ico", to: redirect("/icon.png")

  resource :session, only: %i[new create destroy]

  resources :sites, only: %i[show] do
    post :rotate_tracking_token
    resource :publishing, only: %i[create], controller: "publishing" do
      post :rollback
      get :diff
    end
    resources :ai_audits, only: %i[create]
    resources :experiments, only: %i[create] do
      member do
        post :pause
        post :resume
        post :complete
        post :apply_winner
      end
    end
    resources :section_patches, only: [] do
      member do
        get :preview
        post :apply
        post :revert
        post :dismiss
      end
    end
    resource :simulation, only: %i[create]
  end

  namespace :public, path: nil do
    match "/s/:slug", to: "sites#show", via: %i[get head], as: :site
    post "/s/:slug/events", to: "events#create", as: :site_events
    post "/s/:slug/forms/:form_id/submissions", to: "form_submissions#create", as: :site_form_submissions
    post "/s/:slug/products/:product_key/checkout", to: "checkouts#create", as: :site_product_checkout
    post "/s/:slug/plans/:plan_key/checkout", to: "checkouts#create_plan", as: :site_plan_checkout
  end

  namespace :api do
    namespace :v1 do
      resources :events, only: %i[create]
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # 渲染安装元信息，供浏览器读取应用名称、图标和主题色。
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end

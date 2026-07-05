Rails.application.routes.draw do
  root "dashboard#index"

  resource :settings, only: %i[ show update ] do
    post :test_jackett
  end
  resources :indexers do
    collection do
      get :discover
      post :import_from_jackett
    end
  end
  resources :indexer_apps, only: [] do
    post :sync, on: :member
  end
  resources :sync_runs, only: %i[ index show create ] do
    post :abandon, on: :member
  end
  resource :proxy_activity, only: :show
  resources :arr_apps do
    post :test_connections, on: :collection
    post :test_connection, on: :member
  end
  get "torznab/:jackett_id/api", to: "torznab_proxy#show", as: :torznab_proxy
  get "torznab/:jackett_id/download", to: "torznab_proxy#download", as: :torznab_download_proxy

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end

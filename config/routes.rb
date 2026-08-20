Rails.application.routes.draw do
  # `get "listings" => "listings#index"` sends any GET request for the
  # `/listings` path to the `index` action of ListingsController -- this
  # is the dashboard page showing every current listing.
  get "listings" => "listings#index"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Sends anyone visiting the site's bare root URL ("/") straight to the
  # listings dashboard, so that's the very first thing they see.
  root "listings#index"
end

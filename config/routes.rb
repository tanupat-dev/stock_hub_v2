# frozen_string_literal: true

Rails.application.routes.draw do
  get "ops", to: redirect("/ops/products")

  get "up" => "rails/health#show", as: :rails_health_check

  # ===== OAuth =====
  get "/oauth/tiktok/start", to: "oauth/tiktok#start"
  get "/oauth/tiktok/callback", to: "oauth/tiktok#callback"
  get "/oauth/lazada/start", to: "oauth/lazada#start"
  get "/oauth/lazada/callback", to: "oauth/lazada#callback"

  # ===== Ops =====
  namespace :ops do
    # ✅ NEW PAGE
    get "stock_sync_rollout_page", to: "stock_sync_rollouts#page"

    # Barcode bindings
    post "barcode_bindings/clear", to: "barcode_bindings#clear"
    get "barcode_bindings", to: "barcode_bindings#index"
    post "barcode_bindings/import", to: "barcode_bindings#import"

    # Main pages
    get "products", to: "products#index"
    get "orders_page", to: "orders_page#index"
    get "shopee", to: "shopee#index"
    get "pos_cashier", to: "pos_cashier#index"

    # Returns
    get "returns", to: "returns#index"
    get "returns/shops", to: "returns#shops"
    resources :return_shipments, only: [ :index, :show ]

    resources :products, only: [] do
      collection do
        get :export_skus
      end
    end

    resources :file_batches, only: [ :index ]

    resources :marketplace_connections, only: [ :index, :create, :destroy ] do
      collection do
        patch :update
        get :callback_urls
      end
    end

    resources :sku_imports, only: :create

    resources :orders, only: :index do
      collection do
        post :export_shipping_sheet
        get :export_packing_sheet
      end
    end

    # ===== 🔥 Stock Sync =====
    resource :stock_sync_rollout, only: [ :show ], controller: "stock_sync_rollouts" do
      patch :global, action: :update_global
      patch :prefix_mode, action: :update_prefix_mode
      patch :prefix_list, action: :update_prefix_list
    end

    resources :stock_sync_rollout_shops, only: [], controller: "stock_sync_rollouts" do
      member do
        patch :toggle, action: :update_shop
        post :backfill, action: :backfill_shop
      end
    end
  end

  # ===== Shopee =====
  namespace :shopee do
    post "returns/import", to: "returns#import"
    post "orders/import", to: "orders#import"
    post "stocks/export", to: "stocks#export"
  end

  # ===== POS =====
  namespace :pos do
    resources :exchanges, only: [ :create, :show ] do
      collection do
        post :lookup
      end

      member do
        post :attach_return
        post :attach_new_sale
        post :complete
      end
    end

    resources :retail_returns, only: [ :create, :show ] do
      collection do
        post :lookup
      end

      member do
        post :add_line
        post :complete
      end
    end

    resources :stock_counts, only: [ :create, :show ] do
      member do
        post :upsert_line
        post :confirm
      end
    end

    resources :sales, only: [ :create, :index, :show ] do
      collection do
        post :lookup
      end

      member do
        post :add_line
        patch :update_line
        delete :remove_line
        post :checkout
        post :void
      end
    end

    resources :skus, only: [] do
      collection do
        get :facets
        get :search
      end

      member do
        get :ledger
        post :freeze
        post :unfreeze
      end
    end

    resources :scans, only: :create

    post "barcode_bindings", to: "barcode_bindings#create"
    post "returns/lookup", to: "returns#lookup"
    post "returns/scan", to: "returns#scan"

    post "stock_adjust", to: "stock_adjustments#create"

    resources :oversells, only: [ :index, :show ] do
      member do
        post :resolve
        post :ignore
      end
    end
  end
end

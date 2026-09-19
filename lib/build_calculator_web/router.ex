defmodule BuildCalculatorWeb.Router do
  use BuildCalculatorWeb, :router

  import BuildCalculatorWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BuildCalculatorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # Fetched, never required: the constructor and shared links work signed out
    # and an account only buys the ability to save (CLAUDE.md §1).
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  ## Anything that writes
  #
  # Declared first on purpose: `/builds/new` has to be matched before the
  # `/builds/:id` pattern below, or "new" would be read as an id.
  #
  # The pipeline plug matters as much as the `on_mount`: a signed-out GET to
  # `/builds/new?b=<code>` is how a guest saves, and only the plug stores
  # `current_path/1` (query string included) so log-in can send them back to the
  # build they had assembled.
  scope "/", BuildCalculatorWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{BuildCalculatorWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      live "/builds/new", BuildFormLive, :new
      live "/builds/:id/edit", BuildFormLive, :edit

      live "/library/mine", LibraryLive, :mine
      live "/library/group/:group_id", LibraryLive, :group

      live "/groups", GroupsLive, :index
      live "/groups/:id", GroupLive, :show
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  ## Anything that reads, signed in or not
  #
  # These live in `live_session :current_user` so `@current_scope` is assigned
  # without ever being required: the builder shows «Сохранить» to a guest and
  # sends them through the log-in door, it does not close the door on them.
  scope "/", BuildCalculatorWeb do
    pipe_through :browser

    live_session :current_user,
      on_mount: [{BuildCalculatorWeb.UserAuth, :mount_current_scope}] do
      # A build lives in its encoded form and is shared by link (CLAUDE.md §9).
      # The constructor carries the code in the `b` query parameter, the
      # read-only view in the path — and, once saved, by row id.
      live "/", BuilderLive, :index
      live "/b/:code", BuildViewLive, :show
      live "/builds/:id", BuildViewLive, :saved

      live "/library", LibraryLive, :public

      # CC BY-SA attribution for the Fandom text this app is built on has to
      # reach a guest who never signs in — the same reason `/library` sits in
      # this live_session rather than the authenticated one below.
      live "/sources", SourcesLive, :index

      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete

    # Короткая ссылка на билд. Открывается БЕЗ аккаунта — она для того, кто
    # не регистрировался, — поэтому стоит в этом scope (`pipe_through :browser`,
    # без `:require_authenticated_user`), рядом с остальным, что только читает.
    #
    # `live_session` у неё нет и не может быть: это не LiveView, а редирект на
    # `/b/:code` (см. `ShortLinkController`) — короткий адрес разворачивается
    # в самодостаточный, и дальше работает уже существующий экран просмотра
    # из `live_session :current_user` выше.
    #
    # ⚠️ Ловушки «`new` читается как id» здесь не возникает: под `/s/` нет ни
    # одного литерального роута, с которым `:key` мог бы столкнуться. Заведётся
    # такой — объявлять его выше этой строки, как это сделано у `/builds/new`.
    get "/s/:key", ShortLinkController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", BuildCalculatorWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:build_calculator, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BuildCalculatorWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

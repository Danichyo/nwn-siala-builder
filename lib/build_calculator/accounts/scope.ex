defmodule BuildCalculator.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `BuildCalculator.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.

  ## Гость — это скоуп, а не его отсутствие

  ⚠️ `for_user(nil)` возвращает `%Scope{user: nil}`, а не `nil`. Сайт работает
  без входа (CLAUDE.md §1), то есть «не вошёл» — это **обычный посетитель**,
  а не «вызывающего нет». Пока это было одним значением `nil`, каждый
  вызывающий разбирался сам (`@current_scope && @current_scope.user`), а два
  разных состояния с одинаковым представлением рано или поздно расходятся:
  `on_mount(:require_sudo_mode)` на скоупе гостя падал `nil.user` вместо того,
  чтобы отправить на вход. Через роутер это было недостижимо —
  `:require_authenticated` останавливал раньше, — но это свойство функции,
  а не роутера, и держалось оно на порядке `on_mount`.

  Одно представление у гостя ровно одно: `%Scope{user: nil}`. `nil` скоупом
  больше не является нигде — ни в `Library`, ни в `Query.visible_to/2`.
  """

  alias BuildCalculator.Accounts.User

  @type t :: %__MODULE__{user: User.t() | nil}

  defstruct user: nil

  @doc """
  Creates a scope for the given user.

  Без пользователя — скоуп гостя (`%Scope{user: nil}`), см. заголовок модуля.
  """
  @spec for_user(User.t() | nil) :: t()
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: %__MODULE__{}
end

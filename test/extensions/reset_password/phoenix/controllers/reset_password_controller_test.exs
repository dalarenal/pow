defmodule PowResetPassword.Phoenix.ResetPasswordControllerTest do
  use PowResetPassword.TestWeb.Phoenix.ConnCase

  alias Plug.Conn
  alias Pow.Plug, as: PowPlug
  alias PowResetPassword.{Plug, Store.ResetTokenCache}
  alias PowResetPassword.{Test, Test.Users.User}

  @user %User{id: 1}
  @password "secret1234"

  describe "new/2" do
    test "shows", %{conn: conn} do
      conn = get(conn, Routes.pow_reset_password_reset_password_path(conn, :new))

      assert html = html_response(conn, 200)
      assert html =~ "<label for=\"user_email\">Email</label>"
      assert html =~ "<input id=\"user_email\" name=\"user[email]\" type=\"text\">"
    end

    test "already signed in", %{conn: conn} do
      conn =
        conn
        |> PowPlug.assign_current_user(@user, [])
        |> get(Routes.pow_reset_password_reset_password_path(conn, :new))

      assert_authenticated_redirect(conn)
    end
  end

  describe "create/2" do
    @valid_params %{"user" => %{"email" => "test@example.com"}}
    @invalid_params %{"user" => %{"email" => "invalid@example.com"}}

    test "already signed in", %{conn: conn} do
      conn =
        conn
        |> PowPlug.assign_current_user(@user, [])
        |> get(Routes.pow_reset_password_reset_password_path(conn, :new))

      assert_authenticated_redirect(conn)
    end

    test "with valid params", %{conn: conn, ets: ets} do
      conn         = post conn, Routes.pow_reset_password_reset_password_path(conn, :create, @valid_params)
      [{token, _}] = ResetTokenCache.all([backend: ets], [:_])

      assert_received {:mail_mock, mail}

      assert mail.subject == "Reset password link"
      assert mail.text =~ "\nhttp://localhost/reset-password/#{token}\n"
      assert mail.html =~ "<a href=\"http://localhost/reset-password/#{token}\">"

      assert redirected_to(conn) == Routes.pow_session_path(conn, :new)
      assert get_flash(conn, :info) == "If an account for the provided email exists, an email with reset instructions will be sent to you. Please check your inbox."
    end

    test "with invalid params", %{conn: conn} do
      conn = post conn, Routes.pow_reset_password_reset_password_path(conn, :create, @invalid_params)

      assert redirected_to(conn) == Routes.pow_session_path(conn, :new)
      assert get_flash(conn, :info) == "If an account for the provided email exists, an email with reset instructions will be sent to you. Please check your inbox."
    end

    test "with invalid params and pow_prevent_user_enumeration: false", %{conn: conn} do
      conn =
        conn
        |> Conn.put_private(:pow_prevent_user_enumeration, false)
        |> post(Routes.pow_reset_password_reset_password_path(conn, :create, @invalid_params))

      assert html = html_response(conn, 200)
      assert get_flash(conn, :error) == "No account exists for the provided email. Please try again."
      assert html =~ "<input id=\"user_email\" name=\"user[email]\" type=\"text\" value=\"invalid@example.com\">"
    end
  end

  describe "edit/2" do
    setup %{conn: conn} do
      {:ok, %{token: token}, _conn} =
        conn
        |> PowPlug.put_config(Test.pow_config())
        |> Plug.create_reset_token(%{"email" => "test@example.com"})

      {:ok, token: token}
    end

    test "already signed in", %{conn: conn, token: token} do
      conn =
        conn
        |> PowPlug.assign_current_user(@user, [])
        |> get(Routes.pow_reset_password_reset_password_path(conn, :edit, token))

      assert_authenticated_redirect(conn)
    end

    test "invalid token", %{conn: conn} do
      conn = get conn, Routes.pow_reset_password_reset_password_path(conn, :edit, "invalid")

      assert redirected_to(conn) == Routes.pow_reset_password_reset_password_path(conn, :new)
      assert get_flash(conn, :error) == "The reset token has expired."
    end

    test "valid token", %{conn: conn, token: token} do
      conn = get conn, Routes.pow_reset_password_reset_password_path(conn, :edit, token)

      assert html = html_response(conn, 200)
      assert html =~ "<label for=\"user_password\">Password</label>"
      assert html =~ "<input id=\"user_password\" name=\"user[password]\" type=\"password\">"
      assert html =~ "<label for=\"user_password_confirmation\">Password confirmation</label>"
      assert html =~ "<input id=\"user_password_confirmation\" name=\"user[password_confirmation]\" type=\"password\">"
      assert html =~ "<a href=\"/session/new\">Sign in</a>"
    end
  end

  describe "update/2" do
    @valid_params %{"user" => %{"password" => @password, "password_confirmation" => @password}}
    @invalid_params %{"user" => %{"password" => @password, "password_confirmation" => "invalid"}}

    setup %{conn: conn} do
      {:ok, %{token: token}, _conn} =
        conn
        |> PowPlug.put_config(Test.pow_config())
        |> Plug.create_reset_token(%{"email" => "test@example.com"})

      {:ok, token: token}
    end

    test "already signed in", %{conn: conn, token: token} do
      conn =
        conn
        |> PowPlug.assign_current_user(@user, [])
        |> put(Routes.pow_reset_password_reset_password_path(conn, :update, token, @valid_params))

      assert_authenticated_redirect(conn)
    end

    test "invalid token", %{conn: conn} do
      conn = put conn, Routes.pow_reset_password_reset_password_path(conn, :update, "invalid", @valid_params)

      assert redirected_to(conn) == Routes.pow_reset_password_reset_password_path(conn, :new)
      assert get_flash(conn, :error) == "The reset token has expired."
    end

    test "with valid params", %{conn: conn, token: token} do
      conn = put conn, Routes.pow_reset_password_reset_password_path(conn, :update, token, @valid_params)

      assert redirected_to(conn) == Routes.pow_session_path(conn, :new)
      assert get_flash(conn, :info) == "The password has been updated."

      refute Plug.user_from_token(conn, token)
    end

    test "with invalid params", %{conn: conn, token: token} do
      conn = put conn, Routes.pow_reset_password_reset_password_path(conn, :update, token, @invalid_params)

      assert html = html_response(conn, 200)
      assert html =~ "<label for=\"user_password\">Password</label>"
      assert html =~ "<input id=\"user_password\" name=\"user[password]\" type=\"password\">"
      assert html =~ "<span class=\"help-block\">does not match confirmation</span>"

      changeset = conn.assigns[:changeset]
      assert changeset.errors[:password_confirmation]
      assert changeset.action == :update

      assert Plug.user_from_token(conn, token)
    end

    test "with missing user", %{conn: conn} do
      {:ok, %{token: token}, _conn} =
        conn
        |> PowPlug.put_config(Test.pow_config())
        |> Plug.create_reset_token(%{"email" => "missing@example.com"})

      conn = put conn, Routes.pow_reset_password_reset_password_path(conn, :update, token, @valid_params)

      assert redirected_to(conn) == Routes.pow_session_path(conn, :new)
      assert get_flash(conn, :info) == "The password has been updated."
    end
  end
end

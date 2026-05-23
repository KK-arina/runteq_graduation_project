# test/test_helper.rb
# =============================================================
# テストの共通設定ファイル
# すべてのテストファイルから require される
# =============================================================

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"   # stub を使うために必要。
                          # minitest/mock が読み込まれていないと
                          # Object#stub が定義されないため NoMethodError になる。

# =============================================================
# TestLoginHelper モジュール
# ログイン処理を1箇所にまとめることで、将来ログイン実装が
# 変わっても test_helper.rb だけ修正すれば済む
# =============================================================
module TestLoginHelper
  # log_in_as(user) : 指定ユーザーでログインする
  # post login_path で実際のHTTPリクエストを通じてログインする
  # これにより SessionsController の動作も含めてテストできる
  #
  # 【F-3 追加: terms_agreed_at の自動設定】
  #   F-3 で ApplicationController に redirect_to_terms_agreement_if_needed を追加した。
  #   このフィルターは「ログイン済みかつ terms_agreed_at が nil」のユーザーを
  #   /terms_agreement へ強制リダイレクトする。
  #
  #   テスト内で User.create! したユーザーは terms_agreed_at が nil のため、
  #   ログイン後に全てのリクエストが /terms_agreement にリダイレクトされてしまう。
  #
  #   log_in_as を呼ぶ前に terms_agreed_at を自動設定することで、
  #   既存テストを1件も修正せずに全テストを通過させる。
  #
  #   ただし「未同意ユーザーのテスト」（TermsAgreementControllerTest等）は
  #   テスト内で明示的に update_column(:terms_agreed_at, nil) して未同意状態を作る。
  def log_in_as(user)
    # terms_agreed_at が nil（未同意）のユーザーは同意済みにしてからログインする
    #
    # 【なぜ update_column を使うのか】
    #   update! だとパスワードバリデーション等が再実行される可能性がある。
    #   update_column は指定カラムのみバリデーション・コールバックなしで
    #   直接 DB 更新するため安全かつ高速。
    #
    # 【なぜ terms_agreed_at.nil? のときだけ更新するのか】
    #   TermsAgreementControllerTest のように「未同意状態でテストしたい場合」は
    #   テスト内で明示的に update_column(:terms_agreed_at, nil) している。
    #   log_in_as で上書きしてしまうとそのテストが壊れるため、nil のときのみ設定する。
    if user.terms_agreed_at.nil?
      user.update_column(:terms_agreed_at, Time.current)
    end

    post login_path, params: {
      session: {
        email:    user.email,
        password: "password"  # fixtures で設定したパスワード
      }
    }
  end
end

module ActiveSupport
  class TestCase
    # fixtures :all : test/fixtures/ 以下のすべてのYAMLをテストデータとして読み込む
    fixtures :all
  end
end

# ActionDispatch::IntegrationTest（統合テスト）で
# TestLoginHelper のメソッドが使えるよう組み込む
class ActionDispatch::IntegrationTest
  include TestLoginHelper
end
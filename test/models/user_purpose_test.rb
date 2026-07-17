# test/models/user_purpose_test.rb
#
# ==============================================================================
# UserPurpose（PMVV目標）モデルテスト（I-1: 本リリース分のテスト網羅）
# ==============================================================================
#
# 【このファイルの役割】
#   PMVV目標モデルの「バリデーション」「analysis_state（AI分析状態）enum」
#   「バージョン管理に関わるスコープ（active_for / current_for）」を検証する。
#
# 【バージョン管理についての設計メモ（重要）】
#   「更新するたびに version を +1 して新しい行を作り、旧行を is_active=false にする」
#   という“採番・切り替え”の処理は UserPuposesController 側で行っている。
#   モデル自身は「version の妥当性チェック」と「有効な最新版を取り出すスコープ」だけを
#   担当する。そのためこのモデルテストでは、
#     ・version のバリデーション（必須・整数・1以上）
#     ・active_for / current_for が「有効フラグtrueの中でversion最大」を返すこと
#   を検証する。採番フロー自体はコントローラ/統合テストで担保する。
# ==============================================================================
require "test_helper"

class UserPurposeTest < ActiveSupport::TestCase
  # ============================================================
  # setup: 各テストの前に専用ユーザーを1人作る
  # ============================================================
  # 【なぜ fixtures のユーザーではなく新規作成するのか】
  #   fixtures に user_purposes が定義されていた場合、users(:one) に
  #   既存のPMVVがぶら下がっていると current_for / active_for の
  #   「件数・並び順」を厳密に検証するテストが不安定になる。
  #   テスト専用の新しいユーザーを作れば、そのユーザーのPMVVは
  #   このテスト内で作った分だけになり、検証が確実になる。
  def setup
    @user = User.create!(
      name:                  "PMVVテストユーザー",
      email:                 "user_purpose_test@example.com",
      password:              "password123",
      password_confirmation: "password123",
      # first_login_at が nil だとアプリ側でオンボーディングに誘導されるが、
      # モデルテストでは影響しない。念のため過去日付を入れておく。
      first_login_at:        1.month.ago
    )
  end

  # ============================================================
  # 有効なPMVVの属性をまとめて返すヘルパー
  # ============================================================
  # 【なぜヘルパーにするのか】
  #   PMVVは purpose / mission / vision / value / current_situation の
  #   5フィールドすべてが presence: true（必須）。毎回5項目を書くのは冗長で、
  #   1項目を変えたテスト（例: purposeだけ空）を作るのも大変になる。
  #   overrides で「変えたい項目だけ」上書きできるようにして DRY にする。
  def valid_attrs(overrides = {})
    {
      user:              @user,
      purpose:           "健康でいきいきと長生きすること",
      mission:           "毎日体を動かす習慣を身につけること",
      vision:            "1年後、体力がついて疲れにくい自分になっている",
      value:             "家族との時間を何より大切にする",
      current_situation: "最近は運動不足で、階段でも息が切れる"
    }.merge(overrides)
  end

  # ============================================================
  # バリデーション: 5フィールドの必須チェック
  # ============================================================

  test "5フィールドが揃っていれば有効" do
    purpose = UserPurpose.new(valid_attrs)
    assert purpose.valid?, purpose.errors.full_messages.to_s
  end

  test "purpose / mission / vision / value / current_situation はそれぞれ必須" do
    # 【なぜ配列でまとめて回すのか】
    #   5項目それぞれに「空なら無効」という同じ検証をするため、
    #   ループで回すと重複コードを避けられる（DRY）。
    %i[purpose mission vision value current_situation].each do |field|
      # 対象フィールドだけ空文字にした UserPurpose を作る
      purpose = UserPurpose.new(valid_attrs(field => ""))
      assert_not purpose.valid?, "#{field} が空なのに valid? が true を返した"
      # モデルの presence バリデーションは message: "を入力してください" を使う。
      # エラー配列にこの文言が含まれることを確認する。
      assert_includes purpose.errors[field], "を入力してください",
                      "#{field} の必須エラーメッセージが日本語になっていない"
    end
  end

  test "purpose が500文字を超えると無効" do
    # length: { maximum: 500 } の上限を検証する（境界値テスト）。
    purpose = UserPurpose.new(valid_attrs(purpose: "あ" * 501))
    assert_not purpose.valid?
    assert purpose.errors[:purpose].any?, purpose.errors.full_messages.to_s
  end

  test "purpose がちょうど500文字なら有効" do
    # 上限ちょうど（500文字）は通ることを確認する（境界値テスト）。
    purpose = UserPurpose.new(valid_attrs(purpose: "あ" * 500))
    assert purpose.valid?, purpose.errors.full_messages.to_s
  end

  # ============================================================
  # バリデーション: version（バージョン番号）
  # ============================================================

  test "version が nil なら無効（必須）" do
    # 【nil を明示的に代入する理由】
    #   version は DB デフォルトが 1 のため、指定しないと自動で 1 が入る。
    #   presence バリデーションを確かめるには、あえて nil を入れて検証する。
    purpose = UserPurpose.new(valid_attrs(version: nil))
    assert_not purpose.valid?
    assert purpose.errors[:version].any?, purpose.errors.full_messages.to_s
  end

  test "version が 0 なら無効（1以上であること）" do
    # numericality: { greater_than: 0 } を検証する。
    purpose = UserPurpose.new(valid_attrs(version: 0))
    assert_not purpose.valid?
    assert purpose.errors[:version].any?, purpose.errors.full_messages.to_s
  end

  test "version が整数でない（1.5）なら無効" do
    # numericality: { only_integer: true } を検証する。
    purpose = UserPurpose.new(valid_attrs(version: 1.5))
    assert_not purpose.valid?
    assert purpose.errors[:version].any?, purpose.errors.full_messages.to_s
  end

  # ============================================================
  # analysis_state（AI分析状態）enum
  # ============================================================

  test "analysis_state enum に pending / analyzing / completed / failed が定義されている" do
    assert_includes UserPurpose.analysis_states.keys, "pending",   "pending が未定義"
    assert_includes UserPurpose.analysis_states.keys, "analyzing", "analyzing が未定義"
    assert_includes UserPurpose.analysis_states.keys, "completed", "completed が未定義"
    assert_includes UserPurpose.analysis_states.keys, "failed",    "failed が未定義"
  end

  test "新規作成時の analysis_state は pending（デフォルト）" do
    # schema.rb で analysis_state は default: 0（pending）。
    # 新しいPMVVは「まだAI分析していない=pending」から始まることを確認する。
    purpose = UserPurpose.new(valid_attrs)
    assert purpose.pending?, "新規PMVVの初期状態は pending であること"
  end

  test "analysis_state の述語メソッドが状態と一致する" do
    # モデルに定義された pending? / analyzing? / completed? / failed? が
    # 現在の状態と正しく対応することを確認する。
    purpose = UserPurpose.new(valid_attrs)

    purpose.analysis_state = :analyzing
    assert purpose.analyzing?
    assert_not purpose.completed?

    purpose.analysis_state = :completed
    assert purpose.completed?

    purpose.analysis_state = :failed
    assert purpose.failed?
  end

  # ============================================================
  # スコープ / クラスメソッド（バージョン管理の要）
  # ============================================================

  test "is_active は新規作成時 true（デフォルト）" do
    # schema.rb で is_active は default: true。
    # 「作ったばかりのPMVVは有効版」であることを確認する。
    purpose = UserPurpose.create!(valid_attrs)
    assert purpose.is_active, "新規PMVVは is_active = true であること"
  end

  test "active_for / current_for は有効フラグtrueの中で version 最大を返す" do
    # 【このテストが守っている仕様】
    #   ユーザーがPMVVを何度も更新すると version 1,2,3... の行が積み上がる。
    #   「今の目標」として扱うべきは “is_active=true かつ version が最大” の1件。
    #   active_for は有効な行を version 降順で返し、current_for はその先頭を返す。

    v1 = UserPurpose.create!(valid_attrs(version: 1, is_active: true))
    v2 = UserPurpose.create!(valid_attrs(version: 2, is_active: true))
    # 無効化された古い版（is_active=false）は対象外になるべき
    inactive = UserPurpose.create!(valid_attrs(version: 3, is_active: false))
    # 別ユーザーのPMVVは @user の結果に混ざってはいけない
    other_user_purpose = UserPurpose.create!(
      valid_attrs(user: users(:two), version: 1, is_active: true)
    )

    # current_for: 有効な中で version 最大 → v2
    assert_equal v2, UserPurpose.current_for(@user),
                 "current_for は有効フラグtrueの中で version 最大を返すこと"

    active_ids = UserPurpose.active_for(@user).map(&:id)
    # 有効な v1・v2 は含まれる
    assert_includes active_ids, v1.id
    assert_includes active_ids, v2.id
    # 無効版・他ユーザー分は含まれない
    assert_not_includes active_ids, inactive.id,           "is_active=false は active_for に含めない"
    assert_not_includes active_ids, other_user_purpose.id, "他ユーザーのPMVVは含めない"
    # version 降順（v2 が v1 より前）に並ぶ
    assert active_ids.index(v2.id) < active_ids.index(v1.id),
           "active_for は version 降順で並ぶこと"
  end
end
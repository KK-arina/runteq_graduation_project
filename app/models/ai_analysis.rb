# app/models/ai_analysis.rb
#
# ==============================================================================
# AiAnalysis（AI分析結果）モデル
# ==============================================================================
#
# 【このファイルの役割】
#   AI分析の結果を保存するモデル。
#   週次振り返り（weekly_reflection）またはPMVV（user_purpose）に紐付く。
#
# 【D-9 での変更内容】
#   ① validate :input_snapshot_schema_valid を追加
#   ② input_snapshot_schema_valid プライベートメソッドを追加
#      - purpose_breakdown 分析のみ対象（weekly_reflection はスキップ）
#      - 必須5キー: purpose / mission / vision / value / current_situation
#      - 「キーが存在するかどうか」のみチェック（値の nil・空文字は許容）
#      - with_indifferent_access でシンボルキー・文字列キー両方に対応
#
# 【input_snapshot とは】
#   分析実行時点のPMVVデータを jsonb 形式で保存したスナップショット。
#   後からユーザーがPMVVを更新しても、この分析がどのデータで行われたかを
#   正確に参照できる。18番画面（PMVV詳細）はここから5要素を表示する。
#
# 【なぜバリデーションが必要か】
#   jsonb は自由形式のため、キーが欠落していても DB に保存できてしまう。
#   必須キーが欠落した状態で保存されると 18番画面でキー参照エラーが起きるため、
#   DB保存前にキーの存在を強制チェックする。
#
# 【値の nil・空文字を許容する理由】
#   UserPurpose の各フィールドは allow_blank: true の設計のため、
#   未入力の場合に nil が保存される。build_input_snapshot はそのまま
#   nil を input_snapshot に含める。18番画面では .presence || "未入力" で
#   表示制御するため、nil 値で画面は崩壊しない。
#
# ==============================================================================

class AiAnalysis < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================

  # belongs_to :user_purpose
  # 【optional: true の理由】
  #   週次振り返り分析（analysis_type: :weekly_reflection）の場合は
  #   user_purpose を持たないため、必須にするとバリデーションエラーになる。
  belongs_to :user_purpose,      optional: true

  # belongs_to :weekly_reflection
  # 【optional: true の理由】
  #   PMVV分析（analysis_type: :purpose_breakdown）の場合は
  #   weekly_reflection を持たないため、必須にするとエラーになる。
  belongs_to :weekly_reflection, optional: true

  # ============================================================
  # enum 定義
  # ============================================================

  # analysis_type: どの種類の分析かを示す整数値
  # 【整数値で管理する理由】
  #   DB のカラムは integer 型のため、Rails の enum を使うことで
  #   コード上では :weekly_reflection のようなシンボルで扱えて可読性が上がる。
  enum :analysis_type, {
    weekly_reflection: 0,  # 週次振り返り分析
    purpose_breakdown: 1,  # PMVV目標分析
    monthly_review:    2   # 月次レビュー分析（将来用）
  }

  # ============================================================
  # バリデーション
  # ============================================================

  # analysis_type は必須
  # 【理由】分析の種類が不明なレコードは 18番画面での表示ロジックが動かない
  validates :analysis_type, presence: true

  # 親レコードのいずれかは必須（カスタムバリデーション）
  validate :at_least_one_parent_present

  # ── D-9 追加: input_snapshot のスキーマバリデーション ────────────────────
  #
  # 【validate :input_snapshot_schema_valid を追加する理由】
  #   purpose_breakdown（PMVV分析）の場合、input_snapshot には
  #   purpose / mission / vision / value / current_situation の5キーが必須。
  #   キーが欠落していると 18番画面でキー参照エラーが発生するため、
  #   DB保存前にキーの存在を強制チェックする。
  #
  # 【週次振り返り分析（:weekly_reflection）には適用しない理由】
  #   週次振り返りの input_snapshot は振り返りデータ（reflection 情報）を含み、
  #   PMVV の5キーを持たない設計になっている。
  validate :input_snapshot_schema_valid
  # ────────────────────────────────────────────────────────────────────────────

  # ============================================================
  # コールバック
  # ============================================================

  # before_create :deactivate_previous_analyses
  # 【役割】
  #   同じ user_purpose_id + analysis_type または weekly_reflection_id の
  #   古い分析を is_latest=false にしてから新しい分析を保存する。
  #   これにより「最新の分析は常に1件」という整合性を保てる。
  before_create :deactivate_previous_analyses

  # ============================================================
  # スコープ
  # ============================================================

  # scope :latest: is_latest=true のレコードのみ返す
  # 【用途】最新の分析結果のみを取得したいとき（ダッシュボードのバナー表示等）に使う
  scope :latest,      -> { where(is_latest: true) }

  # scope :for_purpose: 特定のUserPurposeに紐付く分析を返す
  # 【用途】UserPurpose の詳細ページで分析結果を取得するときに使う
  scope :for_purpose, ->(user_purpose) { where(user_purpose: user_purpose) }

  # ============================================================
  # プライベートメソッド
  # ============================================================
  private

  # ----------------------------------------------------------
  # at_least_one_parent_present
  # ----------------------------------------------------------
  # 【役割】
  #   weekly_reflection_id と user_purpose_id の両方が nil の場合は
  #   バリデーションエラーにする。
  #
  # 【なぜこのチェックが必要か】
  #   どちらの親にも紐付いていない分析レコードは「孤立したデータ」になり、
  #   どの画面からも参照されない無意味なレコードになってしまうため。
  def at_least_one_parent_present
    if weekly_reflection_id.blank? && user_purpose_id.blank?
      errors.add(:base, "weekly_reflection_id または user_purpose_id のどちらかは必須です")
    end
  end

  # ----------------------------------------------------------
  # ── D-9 追加: input_snapshot_schema_valid ─────────────────
  # ----------------------------------------------------------
  # 【役割】
  #   purpose_breakdown（PMVV分析）の場合のみ、
  #   input_snapshot に必須の5キーが全て存在するかを検証する。
  #
  # 【必須キー】
  #   purpose / mission / vision / value / current_situation
  #   これら5つは 18番画面（PMVV詳細）が参照するキー。
  #   キーが欠落するとキー参照エラーで画面が崩壊する。
  #
  # 【「キーの存在」のみチェックして「値の中身」はチェックしない理由】
  #   UserPurpose の各フィールドは allow_blank: true の設計のため、
  #   ユーザーが未入力の場合に nil が保存される。
  #   build_input_snapshot はその nil をそのまま input_snapshot に含める。
  #   18番画面では .presence || "未入力" で nil を安全に処理できるため、
  #   nil 値があっても画面は崩壊しない。
  #   バリデーションは「キーが存在するかどうか」のみで十分。
  #
  # 【実装方法の選択: カスタムバリデーションメソッド（gem なし）】
  #   json-schema gem（外部ライブラリ）を使う方法もあるが、
  #   以下の理由でカスタムメソッドを選択した:
  #     - Gemfile の変更が不要（Docker 再ビルド不要）
  #     - テストがシンプルになる
  #     - 今回の要件（5キーの存在チェック）には十分な堅牢性がある
  #
  # 【週次振り返り分析をスキップする理由】
  #   analysis_type が :weekly_reflection の場合、input_snapshot には
  #   PMVV の5キーではなく振り返りデータが入る設計のため。
  #
  # 【input_snapshot が nil の場合もスキップする理由】
  #   実運用では PurposeAnalysisJob の build_input_snapshot が必ず Hash を
  #   返すため nil になることはない。テストの利便性（input_snapshot を省略した
  #   テストが書きやすい）のためスキップ設計にし、ジョブ側の事前チェックで保護する。
  #
  # 【with_indifferent_access を使う理由】
  #   build_input_snapshot はシンボルキー（:purpose 等）で Hash を作るが、
  #   DB から読み出すと文字列キー（"purpose"）になる。
  #   with_indifferent_access を使うことで両方のキー形式に対応できる。
  def input_snapshot_schema_valid
    # 週次振り返り分析の場合はPMVVキーチェックをスキップする
    # 【理由】週次振り返りの input_snapshot はPMVV5キーを持たない設計のため
    return unless purpose_breakdown?

    # input_snapshot が nil または空の場合はスキップする
    # 【理由】実運用ではジョブ側の事前チェックで防がれており、
    #         nil のまま create! まで到達することはない。
    #         テストでの利便性（input_snapshot 省略可）を確保するためスキップ設計にする。
    return if input_snapshot.blank?

    # 必須キーの定義（18番画面が参照するキー）
    # 【なぜ定数ではなくローカル変数にするか】
    #   このメソッド内でのみ使用するためクラス定数にする必要がない。
    required_keys = %w[purpose mission vision value current_situation]

    # with_indifferent_access で文字列キーとシンボルキーの両方に対応する
    # 【例】
    #   snapshot["purpose"] でも snapshot[:purpose] でも同じ値が取れる
    #   DB 保存・読み出しのキー型の違いを吸収できる
    snapshot = input_snapshot.with_indifferent_access

    # 欠落しているキーを抽出する
    # 【reject の動き】
    #   required_keys の各キーに対して「snapshot にキーとして存在するもの」を除外する。
    #   除外されずに残ったキーが「完全に欠落しているキー」になる。
    #
    # 【なぜ present? ではなく key? だけで判定するか】
    #   UserPurpose の各フィールドは allow_blank: true の設計のため、
    #   ユーザーが未入力の場合に nil が保存され、build_input_snapshot が
    #   nil をそのまま input_snapshot に含める。
    #   「キーが存在するが値が nil」は正常なデータのため弾かない。
    #   値の nil・空文字の表示制御は 18番画面の View 側で行う。
    missing_keys = required_keys.reject do |key|
      snapshot.key?(key)
    end

    # 欠落しているキーがある場合はバリデーションエラーを追加する
    if missing_keys.any?
      # エラーを :input_snapshot フィールドに紐付ける
      # 【:base ではなく :input_snapshot にする理由】
      #   どのフィールドに問題があるかを明確にする。
      #   ja.yml の activerecord.attributes.ai_analysis.input_snapshot の
      #   日本語名（"PMVV分析データ"）と組み合わさり、
      #   full_messages で「PMVV分析データ に必須キーが不足しています: ...」と表示される。
      errors.add(
        :input_snapshot,
        "に必須キーが不足しています: #{missing_keys.join(', ')}"
      )

      # ログにも詳細を記録してデバッグを容易にする
      Rails.logger.error "[AiAnalysis] input_snapshot の必須キーが不足: #{missing_keys.join(', ')}, ai_analysis id=#{id || 'new'}"
    end
  end
  # ────────────────────────────────────────────────────────────────────────────

  # ----------------------------------------------------------
  # deactivate_previous_analyses
  # ----------------------------------------------------------
  # 【役割】
  #   新しい分析レコードを作成する前に、同じ親に紐付く古い分析の
  #   is_latest を false にする。
  #
  # 【update_all を使う理由】
  #   each { |r| r.update! } だと件数分の UPDATE SQL が発行される（N+1更新）。
  #   update_all は1回の SQL UPDATE で全件更新できるため効率的。
  def deactivate_previous_analyses
    if user_purpose_id.present?
      AiAnalysis.where(
        user_purpose_id: user_purpose_id,
        analysis_type:   analysis_type,
        is_latest:       true
      ).update_all(is_latest: false)
    end

    if weekly_reflection_id.present?
      AiAnalysis.where(
        weekly_reflection_id: weekly_reflection_id,
        is_latest:            true
      ).update_all(is_latest: false)
    end
  end
end
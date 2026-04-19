# app/controllers/user_purposes_controller.rb
#
# ==============================================================================
# UserPurposesController（PMVV 目標管理コントローラー）
# ==============================================================================
#
# 【このファイルの役割】
#   PMVV（Purpose/Mission/Vision/Value/Current）の入力・更新を管理する。
#   16番（PMVV目標管理ページ）と 17番（PMVV入力ページ）に対応する。
#
# 【アクション一覧】
#   show   → 16番: 現在の PMVV と分析状態を表示する
#   new    → 17番: 新規入力フォームを表示する（PMVV が存在しない場合）
#   create → 17番フォームを送信して新規 PMVV を保存する
#   edit   → 17番: 編集フォームを表示する（PMVV が存在する場合）
#   update → 編集フォームを送信して PMVV を更新保存する
#
# 【バージョン管理の流れ】
#   create: 新しい UserPurpose レコードを作成する
#           → before_save で旧バージョンの is_active が false になる
#           → version は before_validation で自動採番される
#   update: 「更新」は実質 create と同じ（新しいレコードを作成する）
#           → 古いレコードは is_active=false になり履歴として残る
#
# ==============================================================================

class UserPurposesController < ApplicationController
  # ============================================================
  # before_action
  # ============================================================

  # require_login: 未ログインのアクセスをブロックする
  # 【理由】
  #   PMVV はユーザーの個人情報に相当するため、
  #   ログインしていないユーザーはアクセスできないようにする。
  #   ApplicationController に定義された共通メソッドを使う。
  before_action :require_login

  # ============================================================
  # show アクション（16番: PMVV目標管理ページ）
  # ============================================================
  #
  # 【役割】
  #   現在有効な PMVV（is_active=true）を表示する。
  #   analysis_state に応じて UI を切り替える（nil/pending/analyzing/completed/failed）。
  #
  # 【@current_purpose について】
  #   UserPurpose.current_for(current_user) → is_active=true のレコードを1件返す。
  #   存在しない場合は nil → ビューで「目標が未入力」状態を表示する。
  #
  # 【@past_purposes について】
  #   過去のバージョン（is_active=false）の一覧。
  #   バージョン履歴としてビューに表示する。
  def show
    # current_for: is_active=true の最新レコードを取得するクラスメソッド
    @current_purpose = UserPurpose.current_for(current_user)

    # 過去バージョン: is_active=false のレコードをバージョン降順で取得する
    # where.not(is_active: true) ではなく is_active: false で明示する
    @past_purposes = current_user.user_purposes
                                 .where(is_active: false)
                                 .order(version: :desc)
  end

  # ============================================================
  # new アクション（17番: PMVV入力ページ・新規）
  # ============================================================
  #
  # 【役割】
  #   空の UserPurpose インスタンスをビューに渡してフォームを表示する。
  #   フォームの action は user_purposes_path（POST）になる。
  def new
    # new: DB には保存しない空のインスタンスを作成する
    # form_with model: @user_purpose で action と method が自動決定される:
    #   新規（unsaved）→ POST /user_purposes（create アクション）
    @user_purpose = UserPurpose.new
  end

  # ============================================================
  # create アクション
  # ============================================================
  #
  # 【役割】
  #   17番フォームの送信を受けて新しい PMVV を保存する。
  #   保存成功時: analysis_state を pending に設定し AI 分析ジョブをエンキューする。
  #   保存失敗時: エラーを表示してフォームを再表示する。
  #
  # 【analysis_state について】
  #   UserPurpose モデルの enum で pending=0 と定義されているが、
  #   schema.rb の default: 0 により保存時点で自動的に pending になる。
  #   明示的に設定することでコードの意図を明確にする。
  def create
    # build: current_user に紐付いた新しい UserPurpose インスタンスを作成する
    # user_purpose_params: Strong Parameters でホワイトリスト化した入力値
    @user_purpose = current_user.user_purposes.build(user_purpose_params)

    # analysis_state を明示的に pending に設定する
    # 【理由】
    #   schema.rb の default: 0 で pending になるが、
    #   コードを読む人に「保存直後は pending」という意図を明確に伝える。
    @user_purpose.analysis_state = :pending

    if @user_purpose.save
      # 保存成功: AI 分析ジョブをバックグラウンドで実行する
      # perform_later: GoodJob キューに追加して非同期で実行する
      # id を渡す理由: ジョブ引数は JSON シリアライズされるためインスタンスは渡せない
      PurposeAnalysisJob.perform_later(@user_purpose.id)

      # 成功メッセージを flash に設定してリダイレクトする
      # notice: green 系の通知（application.html.erb の 'unlock' に相当）
      redirect_to user_purpose_path,
                  notice: "目標を保存しました。AIによる分析を開始しています..."
    else
      # 保存失敗: エラーメッセージを表示してフォームを再表示する
      # render :new でフォームページを再描画する（リダイレクトではない）
      # @user_purpose にはバリデーションエラーが入っているため
      # shared/form_errors パーシャルがエラーを表示できる
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # edit アクション（17番: PMVV入力ページ・編集）
  # ============================================================
  #
  # 【役割】
  #   現在有効な PMVV を取得してフォームに表示する。
  #   フォームの action は user_purpose_path（PATCH）になる。
  #
  # 【「更新」が実質「新規作成」である理由】
  #   update アクションでは既存レコードを変更するのではなく、
  #   新しいレコードを作成して古いものを is_active=false にする。
  #   これにより履歴が保持される。
  #   ただし UX 上は「更新」として見せるため edit フォームを使う。
  def edit
    # 現在有効な PMVV を取得してフォームに初期値として表示する
    @user_purpose = UserPurpose.current_for(current_user)

    # 現在有効な PMVV が存在しない場合は新規作成ページへリダイレクトする
    unless @user_purpose
      redirect_to new_user_purpose_path,
                  alert: "まだ目標が登録されていません。新規登録してください。"
    end
  end

  # ============================================================
  # update アクション
  # ============================================================
  #
  # 【役割】
  #   編集フォームの送信を受けて PMVV を「更新」する。
  #   実際には新しいレコードを作成して古いものを is_active=false にする。
  #   バージョン番号は before_validation で自動採番される。
  #
  # 【なぜ既存レコードを変更しないのか】
  #   過去の AI 分析結果（ai_analyses）は作成時の PMVV に紐付いているため、
  #   既存レコードを上書きすると履歴の整合性が壊れる。
  #   新しいレコードを作ることで「このバージョンの PMVV で分析した」という
  #   履歴が保持される。
  def update
    # 新しい UserPurpose インスタンスを作成する（既存レコードの変更ではない）
    # これが「更新は実質新規作成」の実装部分
    @user_purpose = current_user.user_purposes.build(user_purpose_params)
    @user_purpose.analysis_state = :pending

    if @user_purpose.save
      # 保存成功（before_save で旧バージョンが is_active=false になる）
      PurposeAnalysisJob.perform_later(@user_purpose.id)

      redirect_to user_purpose_path,
                  notice: "目標を更新しました。AIによる再分析を開始しています..."
    else
      # 保存失敗: フォームを再表示する
      render :edit, status: :unprocessable_entity
    end
  end

  # ============================================================
  # Private メソッド
  # ============================================================
  private

  # user_purpose_params
  # 【役割】
  #   フォームから送信されたパラメータをホワイトリスト化する。
  #   許可していないパラメータ（version, is_active, analysis_state など）は
  #   自動的に除外されてセキュリティを保つ（Strong Parameters）。
  #
  # 【許可するフィールド】
  #   purpose, mission, vision, value, current_situation の5フィールドのみ。
  #   version / is_active / analysis_state はコントローラー側で制御するため除外。
  def user_purpose_params
    params.require(:user_purpose).permit(
      :purpose,
      :mission,
      :vision,
      :value,
      :current_situation
    )
  end
end
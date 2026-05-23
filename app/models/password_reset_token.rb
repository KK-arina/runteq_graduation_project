# app/models/password_reset_token.rb
#
# ==============================================================================
# PasswordResetToken（パスワードリセットトークン）モデル
# ==============================================================================
#
# 【このモデルの役割】
#   パスワードリセット用の「使い捨てトークン」を管理する。
#   ユーザーがパスワードリセットを申請すると、このテーブルに1レコード作られ、
#   メールに含まれるURLのトークンと照合してパスワード変更を許可する。
#
# 【DBスキーマ（schema.rb から確認済み）】
#   id             : bigint (主キー)
#   user_id        : bigint NOT NULL (外部キー、UNIQUEインデックスあり)
#   token_digest   : string NOT NULL (UNIQUE) ← トークンのBCryptハッシュ
#   expires_at     : datetime NOT NULL        ← 有効期限（発行から24時間後）
#   is_used        : boolean DEFAULT false    ← 使用済みフラグ
#   created_at     : datetime NOT NULL
#   updated_at     : datetime NOT NULL
#
# 【user_id の UNIQUE 制約について】
#   schema.rb に unique: true のインデックスがある。
#   1ユーザーにつき1レコードのみ存在できる設計。
#   新しいリセット申請が来たら「find_or_initialize_by」で既存レコードを上書きする。
#
# 【セキュリティ設計】
#   トークン本体（生の文字列）はメールにのみ含まれ、DBには保存しない。
#   DB には BCrypt ハッシュ（token_digest）のみ保存する。
#   これにより DB が漏洩しても攻撃者はトークンを使えない。
#   ← パスワードと同じ考え方（has_secure_password の応用）
#
# 【メソッド一覧】
#   self.generate_token_for(user) → 新規または既存レコードを作成・上書きして
#                                   生のトークン文字列を返す
#   valid?                        → 有効期限内かつ未使用かを true/false で返す
#   expire!                       → is_used を true にして「使用済み」にする
#   self.find_by_raw_token(token) → 生トークンからレコードを検索する
#
# ==============================================================================
class PasswordResetToken < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================
  #
  # belongs_to :user
  #   このトークンが「どのユーザーの」リセット申請かを紐付ける。
  #   Rails の belongs_to はデフォルトで presence バリデーションが付く。
  #   つまり user_id が NULL のレコードは保存できない。
  belongs_to :user

  # ============================================================
  # バリデーション
  # ============================================================
  validates :token_digest, presence: true
  validates :expires_at,   presence: true

  # ============================================================
  # クラスメソッド
  # ============================================================

  # generate_token_for(user)
  #
  # 【役割】
  #   ユーザーのパスワードリセットトークンを生成し、DBに保存する。
  #   既存のレコードがある場合は上書き（upsert）する。
  #   生のトークン文字列（メールURLに埋め込む値）を返す。
  #
  # 【なぜ find_or_initialize_by を使うのか】
  #   user_id に UNIQUE 制約があるため、create! を使うと
  #   2回目の申請で「重複キー」エラーが発生する。
  #   find_or_initialize_by で「既存レコードを探し、なければ新規インスタンス」を
  #   取得してから save! することで、新規・上書きどちらも安全に処理できる。
  #
  # 【SecureRandom.urlsafe_base64(32) について】
  #   ランダムな文字列を生成する Ruby 標準ライブラリのメソッド。
  #   urlsafe_base64 は URL に安全な文字（A-Z a-z 0-9 - _）のみを使う。
  #   32 バイト = 43文字の文字列が生成される（エントロピー256ビット）。
  #   推測困難な十分な長さのトークンになる。
  #
  # 【BCrypt::Password.create について】
  #   生トークンをBCryptでハッシュ化してDBに保存する。
  #   has_secure_password がパスワードに行うのと同じ方法。
  #   BCrypt はハッシュから元の値を復元できない（一方向ハッシュ）。
  #
  # 【24.hours.from_now について】
  #   ActiveSupport が提供するメソッド。
  #   現在時刻から24時間後の Time オブジェクトを返す。
  def self.generate_token_for(user)
    # 生のトークン文字列を生成（URLに埋め込む値）
    raw_token = SecureRandom.urlsafe_base64(32)

    # 既存レコードを探すか、なければ新規インスタンスを作る
    #
    # 【find_or_initialize_by の動作】
    #   DB に user_id が一致するレコードがある → そのインスタンスを返す
    #   ない → User.new(user: user) と同等の未保存インスタンスを返す
    record = find_or_initialize_by(user: user)

    # トークンと有効期限を新しい値で上書きする
    #
    # 【BCrypt::Password.create の cost オプション】
    #   テスト環境では cost: 1 にして高速化する。
    #   本番環境は BCrypt デフォルト（cost: 12）を使う。
    #   Rails.env.test? で環境を判別して切り替える。
    record.token_digest = BCrypt::Password.create(
      raw_token,
      cost: Rails.env.test? ? 1 : BCrypt::Engine::DEFAULT_COST
    )
    record.expires_at = 24.hours.from_now
    record.is_used    = false
    record.save!

    # 生のトークンを返す（この値だけがメールURLに使われる）
    raw_token
  end

  # find_by_raw_token(raw_token)
  #
  # 【役割】
  #   メールURLから取り出した生トークンを使って、
  #   対応する PasswordResetToken レコードを検索して返す。
  #
  # 【なぜ全件を対象に検索するのか】
  #   token_digest は BCrypt ハッシュなのでインデックス検索できない。
  #   有効期限内・未使用のレコードを絞り込んでから BCrypt で照合する。
  #   user_id に UNIQUE 制約があるため件数は最大でも数件（実質1件）しかない。
  #
  # 【BCrypt::Password.new(record.token_digest).is_password?(raw_token) について】
  #   BCrypt::Password.new でハッシュを BCrypt オブジェクトに変換し、
  #   is_password? で「生トークンがこのハッシュに対応するか」を照合する。
  #   これはパスワード認証の user.authenticate(password) と同じ仕組み。
  def self.find_by_raw_token(raw_token)
    return nil if raw_token.blank?

    # 変更前
    candidates = where(is_used: false).where("expires_at > ?", Time.current)

    # 変更後（F-4修正: Bullet N+1警告対応 - userを事前にEager Loadingする）
    #
    # 【なぜ includes(:user) を追加するのか】
    #   find_by_raw_token で取得したレコードに対して、
    #   コントローラーで @token_record.user を呼ぶと
    #   追加のSQLクエリが発生する（N+1問題）。
    #   includes(:user) で user を事前に読み込むことで
    #   余分なクエリを防ぐ。Bullet gem の警告を解消する。
    candidates = where(is_used: false).where("expires_at > ?", Time.current).includes(:user)

    candidates.find do |record|
      BCrypt::Password.new(record.token_digest).is_password?(raw_token)
    rescue BCrypt::Errors::InvalidHash
      false
    end
  end

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # valid_token?
  #
  # 【役割】
  #   このトークンが「今も使える状態か」を true/false で返す。
  #
  # 【チェック項目】
  #   1. is_used が false か（未使用か）
  #   2. expires_at が現在時刻より未来か（有効期限内か）
  #
  # 【注意: Rails の valid? との名前衝突を避けるため valid_token? にする】
  #   ActiveRecord::Base を継承したモデルでは valid? は
  #   「バリデーションを実行して結果を返す」メソッドとして予約されている。
  #   名前が衝突するとバリデーション機能が壊れるため valid_token? とする。
  def valid_token?
    !is_used && expires_at > Time.current
  end

  # expire!
  #
  # 【役割】
  #   このトークンを「使用済み」にする。
  #   パスワード変更完了時に呼ぶ。
  #
  # 【update_column を使う理由】
  #   update! だとバリデーションが再実行される。
  #   update_column は指定カラムのみバリデーションなしで直接 DB 更新する。
  #   トークンの is_used だけを高速に更新するのに適している。
  def expire!
    update_column(:is_used, true)
  end
end
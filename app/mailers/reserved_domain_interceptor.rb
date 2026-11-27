# app/mailers/reserved_domain_interceptor.rb
#
# ==============================================================================
# ReservedDomainInterceptor - 届かない予約ドメイン宛てのメールを送らない
# ==============================================================================
#
# 【なぜ必要か】
#   example.com などは「説明・テスト用」として規格（RFC 2606 / RFC 6761）で予約されており、
#   メールを受け取るサーバーが存在しない。デモ用アカウントがこのドメインで登録されていると、
#   週次レポートなどを送るたびに「届かないメール（バウンス）」が発生する。
#   バウンスが多いと Resend からの送信の評価が下がり、
#   本物のユーザーへのメールまで迷惑メール扱いされやすくなるため、送信の直前で止める。
#
# 【インターセプターとは】
#   Action Mailer が「メールを実際に送る直前」に呼び出す仕組み。
#   delivering_email(message) の中で message.perform_deliveries = false にすると、
#   そのメールは送信されない（エラーにはならない）。
#   全メイラーに効くため、週次レポート・タスク通知などを個別に直す必要がない。
#
# 【登録場所】
#   config/initializers/mail_interceptors.rb（本番環境のみ登録）
class ReservedDomainInterceptor
  # 予約ドメインの判定に使う正規表現
  #
  # 【各部分の意味】
  #   (\A|\.)  : ドメインの先頭、またはドットの直後（"myexample.com" のような別ドメインを巻き込まない）
  #   example\.(com|net|org) : RFC 2606 で予約された3つのドメイン（サブドメインも含む）
  #   example|test|invalid|localhost : RFC 2606 / 6761 で予約されたトップレベルドメイン
  #   \z       : 文字列の末尾（"example.com.evil" のような別ドメインを巻き込まない）
  #   i        : 大文字・小文字を区別しない
  RESERVED_DOMAIN_PATTERN = /(\A|\.)(example\.(com|net|org)|example|test|invalid|localhost)\z/i

  # 上と同じ判定を、PostgreSQL の正規表現で書いたもの（管理画面の集計で使う）
  #
  # 【なぜ別に用意するのか】
  #   管理画面では、デモ・テスト用アカウント（予約ドメインのアドレス）を集計から外す。
  #   ユーザーを1人ずつ Ruby で判定すると全員を読み込むことになるため、
  #   DB の中で絞り込めるように SQL 用の書き方も用意する。
  #
  # 【Ruby の正規表現との違い】
  #   \A（先頭）→ ^、\z（末尾）→ $。大文字小文字は SQL 側で LOWER() してから比べる。
  #   末尾の "." は、Ruby では delete_suffix で取り除いているため、こちらでは \.? で許す。
  #   2つの判定が同じ結果になることは test/models/user_countable_test.rb で確かめている。
  #
  # 【シングルクォートで書く理由】
  #   ダブルクォートだと Ruby が \. を特別な文字として扱ってしまうため、
  #   書いたとおりの文字列のまま PostgreSQL に渡せるシングルクォートにしている。
  RESERVED_DOMAIN_SQL_PATTERN = '(^|\.)(example\.(com|net|org)|example|test|invalid|localhost)\.?$'.freeze

  # Action Mailer から、メール送信の直前に呼ばれるメソッド
  def self.delivering_email(message)
    # 宛先（to）のうち、予約ドメインではないものだけを残す
    deliverable = Array(message.to).reject { |address| reserved?(address) }

    if deliverable.empty?
      # 届く宛先が1つもなければ、送信そのものを中止する
      message.perform_deliveries = false

      # 【メールアドレスをログに出さない理由】
      #   メールアドレスは個人情報のため。件名だけ残せば、どのメールが止まったか分かる。
      Rails.logger.info "[ReservedDomainInterceptor] 予約ドメイン宛てのため送信を中止しました: " \
                        "subject=#{message.subject}"
    else
      # 届く宛先だけに絞って送る（複数の宛先が混ざっていた場合）
      message.to = deliverable
    end
  end

  # メールアドレスのドメインが予約ドメインかどうかを判定する
  def self.reserved?(address)
    # "@" より後ろをドメインとして取り出す（"@" がない不正な値は空文字になり、予約扱いしない）
    domain = address.to_s.split("@", 2).last.to_s

    # 末尾に "." が付いた表記（"example.com."）でも判定できるように取り除く
    domain.delete_suffix(".").match?(RESERVED_DOMAIN_PATTERN)
  end
end

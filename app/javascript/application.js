// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// =============================================================================
// Render 無料枠のスリープ復帰・再起動時に起きる Turbo 通信失敗への対策
// （ブランチ: feature/fix-turbo-cold-start-network-error）
// -----------------------------------------------------------------------------
// 【背景】
//   Render 無料枠は15分アクセスが無いとスリープし、復帰直後は 503 を返したり
//   通信自体が失敗（TypeError: Failed to fetch）したりする。
//   Turbo はページ遷移の通信失敗時、自分で通常遷移（フルリロード）に切り替える
//   仕組み（turbo:reload / reason: "request_failed"）を元々持っているため、
//   通信断そのものへの画面遷移対策はここでは行わない（重複させない）。
//   ただし Turbo は失敗したエラーを再 throw するので、それが
//   「未処理の Promise」として Sentry に毎回届いてしまう。
//
// 【このブロックがやること】
//   1. Turbo 起因の通信失敗エラーの「オブジェクトそのもの」を記録する
//   2. Sentry へ送る直前に、次のものだけを除外する
//      2-a. 1 で記録したものと同一のエラー（通信断）
//      2-b. Turbo が読み込みを中止したときの AbortError
//           （ブランチ: fix/sentry-ignore-turbo-abort で追加）
//   3. Turbo のページ遷移が 503 を受けたら、1回だけ通常遷移でやり直す
//
// 【即時実行関数 (() => { ... })() で囲む理由】
//   中の変数（turboNetworkErrors など）を外に漏らさず、
//   他のファイルの同名変数と衝突しないようにするため。
//
// 【import より下に書く理由】
//   import 文は必ずファイル先頭に置くルール（ES モジュールの仕様）。
//   Turbo の読み込み後にイベント登録しても、ページ遷移はユーザー操作の後に
//   起きるので取りこぼしは無い。
// =============================================================================
(() => {
  // ---------------------------------------------------------------------------
  // 1. Turbo 起因の「通信失敗エラー」を記録する
  // ---------------------------------------------------------------------------

  // WeakSet = オブジェクトを「入っているか」だけ覚えておく入れ物。
  // 普通の配列と違い、不要になったエラーは自動でメモリから解放されるため、
  // 長時間開きっぱなしのページでもメモリが増え続けない。
  const turboNetworkErrors = new WeakSet()

  // 各ブラウザが通信断のときに出すエラー文言。
  //   Chrome / Android WebView（LINE 内蔵ブラウザ含む）: "Failed to fetch"
  //   Safari / iOS: "Load failed"
  //   Firefox: "NetworkError when attempting to fetch resource."
  const NETWORK_ERROR_PATTERN = /Failed to fetch|Load failed|NetworkError when attempting to fetch resource/

  // Turbo は通信に失敗すると、このイベントを発火してから同じエラーを再 throw する。
  // （Drive のページ遷移・フォーム送信・フレーム読み込み・プリフェッチ共通）
  document.addEventListener("turbo:fetch-request-error", (event) => {
    // event.detail.error が、あとで Sentry に届くエラーと「同一のオブジェクト」
    const error = event.detail && event.detail.error

    // 通信断（TypeError + 上記の文言）だけを記録する。
    // Turbo の try は画面描画の処理まで囲んでいるため、描画中のバグなど
    // 本物のアプリのエラーまで記録（＝Sentry から除外）しないように絞り込む。
    if (error instanceof TypeError && NETWORK_ERROR_PATTERN.test(error.message)) {
      turboNetworkErrors.add(error)
    }
  })

  // ---------------------------------------------------------------------------
  // 2-b 用: Turbo が読み込みを中止したときの AbortError かどうかを判定する
  //         （ブランチ: fix/sentry-ignore-turbo-abort で追加）
  // ---------------------------------------------------------------------------
  //
  // 【なぜ起きるのか】
  //   Turbo は、ページの読み込み中に別の画面への移動が始まると、
  //   前の読み込みを AbortController で中止して新しい移動を優先する。
  //   このとき出る AbortError（"signal is aborted without reason"）は正常な中止の合図だが、
  //   LINE アプリ内ブラウザ（Android WebView）などでは「未処理の Promise」として表に出て、
  //   Sentry の自動収集に拾われることがある。利用者への影響は無い。
  //
  // 【なぜ 1 と同じ「同一オブジェクト」の方式を使わないのか】
  //   Turbo は中止のときに turbo:fetch-request-error を発火しないため、
  //   事前にエラーを記録できない。そこで、Sentry に届いたエラーの中身で判定する。
  //
  // 【除外するのは次の2つをどちらも満たすときだけ】
  //   ① エラーの名前が "AbortError"（読み込みの中止）
  //   ② スタックトレース（エラーが起きた場所の記録）に Turbo のファイルが含まれる
  //      本番では importmap により /assets/turbo.min-xxxx.js のようなファイル名になる。
  //   アプリ自身のコードで起きた AbortError や、スタックトレースが無いエラーは
  //   除外しない（＝本物の不具合を見逃さない安全側）。
  const TURBO_FILE_PATTERN = /turbo/i

  const isTurboAbortError = (event, original) => {
    // ① 名前が AbortError でなければ対象外
    //    （DOMException も Error と同じく name を持つ）
    if (!original || original.name !== "AbortError") return false

    // ② Sentry のイベントに入っているスタックトレースを調べる
    //    event.exception.values: エラー（原因が連なる場合は複数）の一覧
    //    stacktrace.frames: 呼び出し元から順に並んだ「どのファイルの何行目か」の一覧
    const values = (event && event.exception && event.exception.values) || []

    return values.some((value) => {
      const frames = (value.stacktrace && value.stacktrace.frames) || []
      return frames.some((frame) =>
        TURBO_FILE_PATTERN.test(frame.filename || frame.abs_path || "")
      )
    })
  }

  // ---------------------------------------------------------------------------
  // 2. Sentry: 除外対象のエラーだけを送信対象から外す
  // ---------------------------------------------------------------------------

  // Sentry は本番のみ layout の <head> で読み込まれる（#I-5）。
  // 開発・テスト環境では window.Sentry が無いので、この処理は丸ごと飛ばされる。
  // addEventProcessor が無い古い SDK の場合も何もしない（＝何も除外しない安全側）。
  if (window.Sentry && typeof window.Sentry.addEventProcessor === "function") {
    // addEventProcessor = Sentry がエラーを送る直前に呼ぶ関数を登録する公開 API。
    // null を返すとそのイベントは送信されない。
    // layout の Sentry.init を書き換えずに済むので、既存設定を壊すリスクが無い。
    window.Sentry.addEventProcessor((event, hint) => {
      // hint.originalException = Sentry が捕まえた元のエラーオブジェクト
      const original = hint && hint.originalException

      // 2-a. 時刻ではなく「同一オブジェクトかどうか」で判定する。
      // 同じ時刻に起きた別の fetch の本物のエラー（CSP ブロック等）は
      // 別オブジェクトなので除外されず、きちんと Sentry に届く。
      if (original && typeof original === "object" && turboNetworkErrors.has(original)) {
        return null
      }

      // 2-b. Turbo が読み込みを中止したときの AbortError（fix/sentry-ignore-turbo-abort で追加）
      if (isTurboAbortError(event, original)) {
        return null
      }

      // それ以外はすべて通常どおり送信する
      return event
    })
  }

  // ---------------------------------------------------------------------------
  // 3. Turbo のページ遷移が 503 を受けたら、1回だけ通常遷移でやり直す
  // ---------------------------------------------------------------------------

  // sessionStorage のキーの接頭辞（他の保存データと区別するため）
  const RETRY_KEY_PREFIX = "hf:turbo503retry:"

  // 同じ URL の再試行は60秒に1回まで。
  // Render 障害・デプロイ失敗などで 503 が続いても無限リロードにならないための上限。
  const RETRY_WINDOW_MS = 60 * 1000

  // Turbo がレスポンスを画面に反映する直前に呼ばれるイベント（キャンセル可能）
  document.addEventListener("turbo:before-fetch-response", (event) => {
    const fetchResponse = event.detail && event.detail.fetchResponse

    // 503 以外（正常・404・422・500 など）は Turbo の通常処理に任せる
    if (!fetchResponse || fetchResponse.statusCode !== 503) return

    // Turbo Drive の「ページ遷移」だけを対象にする。
    // Turbo はイベントを発生源の要素で発火する:
    //   フォーム送信 → form 要素 / フレーム → turbo-frame / プリフェッチ → a 要素
    //   ページ遷移   → document.documentElement（<html>）
    // フォーム送信を再実行すると入力が二重送信されるため、ページ遷移以外は触らない。
    if (event.target !== document.documentElement) return

    // 失敗したページの URL（リダイレクト後の最終 URL）
    const url = fetchResponse.response && fetchResponse.response.url
    if (!url) return

    const key = RETRY_KEY_PREFIX + url

    // 前回この URL で再試行した時刻を読む。
    // sessionStorage が使えない環境（プライベートモード等）では、
    // 回数制限ができず無限ループの恐れがあるので、再試行自体をしない。
    let lastRetryAt = 0
    try {
      lastRetryAt = Number(sessionStorage.getItem(key)) || 0
    } catch (_error) {
      return
    }

    // 60秒以内に再試行済みなら、もうやり直さず Turbo の通常処理（503画面表示）に任せる
    if (Date.now() - lastRetryAt < RETRY_WINDOW_MS) return

    // 今回の再試行時刻を記録する（記録できなければ安全のため再試行しない）
    try {
      sessionStorage.setItem(key, String(Date.now()))
    } catch (_error) {
      return
    }

    // Turbo が Render の 503 ページを画面に描画する標準動作を止める
    event.preventDefault()

    // ブラウザ標準の通常遷移でやり直す。通常遷移は Turbo を通らないので、
    // ここから再びこのイベントが連鎖することはない。
    window.location.href = url
  })
})()
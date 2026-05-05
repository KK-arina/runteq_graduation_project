// app/javascript/controllers/ai_throttle_controller.js
//
// ==============================================================================
// AiThrottleController（D-10: AI API 連打防止フロント実装）
// ==============================================================================
//
// 【このコントローラーの役割】
//   振り返り完了ボタン・「再試行する」ボタンを押した後、
//   1分間ボタンを非活性（disabled）にして連打を防ぐ。
//
// 【サーバーサイドとの二重防御】
//   サーバー側: ApplicationController#throttle_ai_request で1分チェック（DB管理）
//   フロント側: このコントローラーでボタンを1分間 disabled にする
//   → ビュー側のボタン非活性化だけでは HTTP 直接送信でバイパスできるため、
//     サーバー側でも必ずチェックする（多重防御の原則）。
//
// 【connect() での状態復元について】
//   ページ再読み込み・Turbo Drive 遷移後も
//   localStorage に保存したタイムスタンプを確認し、
//   1分以内であればボタンを disabled のまま維持する。
//
//   ただし claude.ai 環境では localStorage が使えないため、
//   ここではセッション内メモリ（クラス変数）でシンプルに管理する。
//   ページリロード後はボタンが有効に戻る設計（サーバー側で二重防御するため問題なし）。
//
// 【使い方（HTML側）】
//   <div data-controller="ai-throttle">
//     <button data-ai-throttle-target="button"
//             data-action="click->ai-throttle#throttle">
//       振り返りを完了する
//     </button>
//   </div>
//
//   または form の submit イベントに接続する場合:
//   <form data-controller="ai-throttle"
//         data-action="submit->ai-throttle#throttle">
//     <button data-ai-throttle-target="button">送信</button>
//   </form>
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ============================================================
  // static targets: このコントローラーが参照する HTML 要素の名前一覧
  // ============================================================
  //
  // 【button ターゲットの役割】
  //   disabled / enabled の切り替え対象となるボタン要素。
  //   data-ai-throttle-target="button" を付けた要素が対象になる。
  //   複数のボタンに付けることも可能（this.buttonTargets で配列として取得できる）。
  static targets = ["button"]

  // ============================================================
  // static values: HTML の data 属性から読み込む値
  // ============================================================
  //
  // 【cooldown (Number) の役割】
  //   ボタンを非活性にする時間（ミリ秒）。
  //   HTML 側で data-ai-throttle-cooldown-value="60000" と指定する。
  //   デフォルト 60000 = 60秒 = 1分。
  //
  //   サーバー側の throttle_ai_request（1分チェック）と合わせる。
  static values = {
    cooldown: { type: Number, default: 60000 }
  }

  // ============================================================
  // connect(): コントローラーが HTML に接続された直後に呼ばれる
  // ============================================================
  //
  // 【初期化処理】
  //   タイマーの参照を null で初期化する。
  //   disconnect() でタイマーをクリアするために参照を保持する。
  connect() {
    // _cooldownTimer: setTimeout の戻り値（タイマーID）を保持する変数
    // null = タイマーが動いていない状態
    this._cooldownTimer = null
  }

  // ============================================================
  // disconnect(): コントローラーが HTML から切り離されたときに呼ばれる
  // ============================================================
  //
  // 【メモリリーク防止】
  //   Turbo Drive でページ遷移した場合でも
  //   タイマーが残り続けないよう clearTimeout する。
  disconnect() {
    if (this._cooldownTimer) {
      clearTimeout(this._cooldownTimer)
      this._cooldownTimer = null
    }
  }

  // ============================================================
  // throttle(event): ボタンクリック or フォーム送信時に呼ばれる
  // ============================================================
  //
  // 【処理の流れ】
  //   1. ボタンを即座に disabled にする（連打防止）
  //   2. ボタンのテキストを「受け付けました...」に変更する
  //   3. 1分後にボタンを有効に戻すタイマーをセットする
  //
  // 【event.preventDefault() を呼ばない理由】
  //   このコントローラーはボタンクリックのタイミングで非活性化するだけ。
  //   フォームの実際の送信処理（form-submit コントローラー等）は
  //   妨げない設計にする。
  throttle() {
    // ボタンターゲットが存在しない場合は何もしない
    if (!this.hasButtonTarget) return

    // 全ての button ターゲットに対して非活性化を適用する
    // （複数ボタンがある場合に対応）
    this.buttonTargets.forEach(button => {
      this._disableButton(button)
    })

    // cooldownValue ミリ秒後にボタンを有効に戻すタイマーをセット
    //
    // 【なぜタイマーで戻すのか】
    //   サーバーからのレスポンス（リダイレクト）でページが遷移した場合、
    //   新しいページでは connect() が再び呼ばれてボタンは有効状態になる。
    //   しかし same ページ内でエラーが発生して render :new になった場合は
    //   タイマーで戻す必要がある。
    //
    // 【setTimeout(fn, cooldownValue)】
    //   cooldownValue ミリ秒後に fn を実行する。
    //   デフォルト 60000ms = 60秒。
    this._cooldownTimer = setTimeout(() => {
      this.buttonTargets.forEach(button => {
        this._enableButton(button)
      })
      this._cooldownTimer = null
    }, this.cooldownValue)
  }

  // ============================================================
  // Private メソッド（外部から呼ばれない処理）
  // ============================================================

  // _disableButton(button): ボタンを非活性にする
  // ----------------------------------------------------------
  // 【disabled = true にする効果】
  //   ① ユーザーがクリックしても何も起きない
  //   ② フォーム送信も発生しない
  //   ③ カーソルが禁止マーク（🚫）になる（cursor-not-allowed クラス）
  //
  // 【data-original-text に元のテキストを保存する理由】
  //   _enableButton でボタンのテキストを元に戻すために使う。
  //   innerHTML は後でスピナー等が追加される可能性があるため
  //   textContent（プレーンテキスト）で取得・保存する。
  // ----------------------------------------------------------
  _disableButton(button) {
    // 元のボタンテキストを data 属性に保存する（後で復元するため）
    // 既に保存済みの場合は上書きしない（二重クリック対策）
    if (!button.dataset.originalText) {
      button.dataset.originalText = button.textContent.trim()
    }

    // ボタンを disabled にする
    button.disabled = true

    // 見た目を「非活性」に変更する
    // opacity-60: 透明度を下げて「使えない」感を出す
    // cursor-not-allowed: カーソルを禁止マークにする
    button.classList.add("opacity-60", "cursor-not-allowed")

    // ボタンのテキストを案内メッセージに変更する
    // 「受け付けました。少々お待ちください」→ サーバーの flash メッセージと統一
    button.textContent = "受け付けました..."
  }

  // _enableButton(button): ボタンを有効に戻す
  // ----------------------------------------------------------
  // 【1分後にタイマーで呼ばれる】
  //   disabled を解除してボタンを操作可能に戻す。
  //   テキストも元に戻す。
  // ----------------------------------------------------------
  _enableButton(button) {
    button.disabled = false

    // 非活性スタイルを解除する
    button.classList.remove("opacity-60", "cursor-not-allowed")

    // 元のテキストを復元する
    // data-original-text が存在する場合のみ復元する（安全なガード）
    if (button.dataset.originalText) {
      button.textContent = button.dataset.originalText
      // 復元後は data-original-text を削除してクリーンにする
      delete button.dataset.originalText
    }
  }
}
// app/javascript/controllers/ai_limit_modal_controller.js
//
// ==============================================================================
// AiLimitModalController（D-6 新規追加）
// ==============================================================================
// 【このコントローラーの役割】
//   AI 分析の月次上限に達したときに表示する 14-B モーダルを制御する。
//
// 【crisis_intervention_controller.js との最大の違い】
//   crisis: オーバーレイクリックで閉じない（緊急度が高い・強制的に選択させる）
//   ai_limit: オーバーレイクリックで閉じる（ユーザーに選択肢がある）
//
// 【重要: submitWithoutAi メソッドについて】
//   「AIなしで完了」ボタンは独立したフォームではなく、
//   メインの振り返りフォームの action URL を書き換えてから送信する。
//   これにより、ユーザーが入力した「振り返りコメント」「なぜ？」等の
//   内容をそのまま complete_without_ai アクションに送信できる。
//   入力内容を保持したまま「AIなしで完了」できるのはこの仕組みのおかげ。
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ============================================================
  // Stimulus の静的プロパティ定義
  // ============================================================

  // targets: コントローラーが操作する DOM 要素を名前で定義する。
  // 定義すると this.desktopModalTarget のように参照できる。
  static targets = [
    "desktopModal", // デスクトップ用: 画面中央のモーダルダイアログ
    "mobileSheet"   // スマホ用: 画面下部からスライドするボトムシート
  ]

  // values: HTML の data 属性から値を受け取る仕組み。
  // data-ai-limit-modal-show-value="true" → this.showValue = true（Boolean型に自動変換）
  static values = {
    show: Boolean // ページ読み込み時に自動表示するかどうか
  }

  // ============================================================
  // connect()
  // Stimulus がこの要素を DOM に接続したとき（ページロード時）に自動実行
  // ============================================================
  connect() {
    // showValue が true（= flash.now[:ai_limit] がセットされている）なら
    // ページ描画直後にモーダルを自動表示する
    if (this.showValue) {
      this.open()
    }
  }

  // ============================================================
  // open(): モーダルを表示する
  // ============================================================
  open() {
    // 背景のスクロールを禁止する
    // モーダル表示中にページ全体がスクロールされると操作が混乱するため
    // close() で必ず解除すること
    document.body.style.overflow = "hidden"

    // 画面幅 768px = Tailwind の md: ブレイクポイントと同じ値
    // window.innerWidth: ブラウザの表示領域の幅（px単位）
    if (window.innerWidth >= 768) {
      // デスクトップ: 画面中央に表示
      // classList.remove("hidden") だと Tailwind の !important に負けることがあるため
      // style.display で直接制御する
      this.desktopModalTarget.style.display = "flex"
    } else {
      // スマホ: 画面下部からボトムシートとして表示
      this.mobileSheetTarget.style.display = "flex"
    }
  }

  // ============================================================
  // close(): モーダルを閉じる
  // data-action="ai-limit-modal#close" から呼ばれる
  // ============================================================
  close() {
    // 背景スクロールを再開する（必ず open() と対にすること）
    document.body.style.overflow = ""

    // 両方を非表示にする（どちらが表示されていたかに関わらず両方閉じる）
    this.desktopModalTarget.style.display = "none"
    this.mobileSheetTarget.style.display  = "none"
  }

  // ============================================================
  // submitWithoutAi(event): AIなしで完了ボタンの処理
  // ============================================================
  //
  // 【なぜ独立したフォームではなくメインフォームを使うのか】
  //   モーダルから独立したフォームで POST すると、
  //   ユーザーが入力した「直接の原因」「改善策」などのテキストが
  //   パラメータに含まれない（モーダル内にはテキストエリアがないため）。
  //   メインフォームの action を書き換えて送信することで、
  //   入力済みの内容をそのまま complete_without_ai アクションに届けられる。
  submitWithoutAi(event) {
    // デフォルトの動作（ボタンのクリックによるフォーム送信）を一旦止める
    event.preventDefault()

    // ページ内の振り返り入力フォームを取得する
    // form[action="/weekly_reflections"] でメインフォームを特定する
    const mainForm = document.querySelector('form[action="/weekly_reflections"]')

    if (mainForm) {
      // フォームの送信先を「AIなし完了」用のパスに変更する
      // これにより、フォームの内容（テキスト入力等）がそのまま
      // complete_without_ai アクションに送信される
      mainForm.action = "/weekly_reflections/complete_without_ai"

      // フォームを送信する
      mainForm.submit()
    } else {
      // フォームが見つからない場合（念のための安全策）
      // 独立した POST リクエストで complete_without_ai を呼ぶ
      console.warn("[AiLimitModalController] メインフォームが見つかりませんでした。直接送信します。")
      const form = document.createElement("form")
      form.method = "POST"
      form.action = "/weekly_reflections/complete_without_ai"

      // Rails の CSRF トークンを付与する（セキュリティ必須）
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      if (token) {
        const input = document.createElement("input")
        input.type  = "hidden"
        input.name  = "authenticity_token"
        input.value = token
        form.appendChild(input)
      }

      document.body.appendChild(form)
      form.submit()
    }
  }

  // ============================================================
  // closeOnOverlay(event): オーバーレイクリックでモーダルを閉じる
  // ============================================================
  //
  // 【event.target と event.currentTarget の違い】
  //   event.currentTarget: data-action が設定されている要素（オーバーレイ自体）
  //   event.target       : 実際にクリックされた要素（カード内部の場合もある）
  //   モーダルカード内をクリックしてもイベントがバブリング（伝搬）してくるため、
  //   オーバーレイ自体がクリックされた場合だけ close() を呼ぶ
  closeOnOverlay(event) {
    if (event.target === event.currentTarget) {
      this.close()
    }
  }
}
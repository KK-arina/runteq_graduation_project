// app/javascript/controllers/habit_record_controller.js
// =============================================================
// Stimulusコントローラー：習慣記録チェックボックスの即時保存を管理する
// 
// Stimulusの基本的な考え方：
// - Controller: JS処理のクラス（このファイル）
// - Target    : JSから操作したいHTML要素（checkboxなど）
// - Value     : HTML側から渡す値（URLなど）
// - Action    : イベント（change など）とメソッドの紐付け
// =============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ---- Targets の定義 ----
  // data-habit-record-target="checkbox" と data-habit-record-target="loading"
  // の要素を this.checkboxTarget, this.loadingTarget で参照できるようにする
  static targets = ["checkbox", "loading"]

  // ---- Values の定義 ----
  // HTML側の data-habit-record-***-value 属性から値を取得する
  // createUrl: 新規作成時のPOST URL
  // updateUrl: 更新時のPATCH URL
  // recordId : 既存レコードのID（0 = まだDBに存在しない）
  static values = { createUrl: String, updateUrl: String, recordId: Number }

  // ---- toggle メソッド ----
  // チェックボックスが変更されたときに呼び出される（data-action="change->habit-record#toggle"）
  async toggle() {
    const checkbox  = this.checkboxTarget
    const completed = checkbox.checked  // true（チェックあり）or false（チェックなし）

    // ローディング状態を開始
    // チェックボックスを無効化してローディングアイコンを表示する
    this._setLoadingState(true)

    try {
      // ---- HTTPリクエストを送信 ----
      // recordId が 0 の場合 → まだDBに記録がない → POST（新規作成）
      // recordId が 1以上の場合 → 既にDBに記録がある → PATCH（更新）
      const url    = this.recordIdValue === 0 ? this.createUrlValue : this.updateUrlValue
      const method = this.recordIdValue === 0 ? "POST" : "PATCH"

      // Promise.race : fetchとタイムアウトを競わせ、先に終わった方を採用する
      // 10秒以内にレスポンスが来なければタイムアウトエラーにする
      const response = await Promise.race([
        fetch(url, {
          method,
          headers: {
            // CSRF対策トークン: RailsはこれがないとPOST/PATCHを拒否する
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
            // Turbo Streamのレスポンスを要求する（サーバー側で respond_to format.turbo_stream が動く）
            "Accept":       "text/vnd.turbo-stream.html",
            // フォームデータ形式で送信することを宣言
            "Content-Type": "application/x-www-form-urlencoded"
          },
          // チェックボックスの状態を "completed=1" or "completed=0" として送信
          body: `completed=${completed ? "1" : "0"}`
        }),
        // app/javascript/controllers/habit_record_controller.js
        // （該当箇所のみ抜粋）

        // ✅ タイムアウトを 10000ms(10秒) → 8000ms(8秒) に変更
        // 理由: 10秒は体感として「フリーズしたかも」と感じる長さ
        //       8秒でも十分な待機時間を確保しつつ、UXが向上する
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error("timeout")), 8000)
        )
      ])

      // HTTPエラー（4xx, 5xx）があればエラーを投げる
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      // レスポンスのTurbo StreamのHTML文字列を取得して画面に反映する
      // window.Turbo.renderStreamMessage がTurboのDOM更新処理を担う
      const responseText = await response.text()
      window.Turbo.renderStreamMessage(responseText)

    } catch (error) {
      // ---- エラー時のロールバック ----
      // 通信失敗やタイムアウトの場合、チェックボックスを元の状態に戻す
      // ユーザーに「操作は失敗した」と視覚的に伝える
      checkbox.checked = !completed
      console.error("保存エラー:", error)
    } finally {
      // 成功・失敗に関わらず、ローディング状態を終了する
      // finally : try/catchの後に必ず実行されるブロック
      this._setLoadingState(false)
    }
  }

  // ---- ローディング状態の制御 ----
  // isLoading: true のとき → チェックボックス無効化 + ローディングアイコン表示
  // isLoading: false のとき → チェックボックス有効化 + ローディングアイコン非表示
  _setLoadingState(isLoading) {
    this.checkboxTarget.disabled = isLoading
    if (isLoading) {
      this.loadingTarget.removeAttribute("hidden")
    } else {
      this.loadingTarget.setAttribute("hidden", "")
    }
  }
}
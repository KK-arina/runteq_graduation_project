// app/javascript/controllers/task_toggle_controller.js
//
// ==============================================================================
// TaskToggleController（C-2 修正: tab パラメータを fetch に追加）
// ==============================================================================
//
// 【C-2 修正内容】
//   fetch のリクエストボディに現在のタブ情報（tab）を追加する。
//
// 【なぜ tab を送る必要があるのか】
//   コントローラーの toggle_complete アクションは
//   「完了→未完了」のとき、どのリスト（active-tasks-list-all など）に
//   タスクを prepend するかを tab の値で決定する。
//
//   tab を送らないと params[:tab] が nil になり、
//   常に "all" タブのリストに prepend されてしまう。
//   例: Must タブを見ているとき完了を外すと
//       active-tasks-list-must ではなく active-tasks-list-all に追加されてしまう。
//
// 【tab の取得方法】
//   現在の URL のクエリパラメータ（?tab=must など）を
//   URLSearchParams で取得する。
//   URL に tab パラメータがない場合は "all" をデフォルトにする。
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url:    String,
    taskId: Number
  }

  async toggle(event) {
    const checkbox = event.target

    // 現在の URL から tab パラメータを取得する
    // 例: /tasks?tab=must → "must"
    // 例: /tasks → "all"（tab パラメータがない場合のデフォルト）
    //
    // URLSearchParams:
    //   ブラウザ標準の API。URL のクエリ文字列（?以降）をパースして
    //   key-value のオブジェクトとして扱えるようにする。
    //   new URLSearchParams(window.location.search) で
    //   現在のページの URL のクエリ文字列を取得する。
    const currentTab = new URLSearchParams(window.location.search).get("tab") || "all"

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept":       "text/vnd.turbo-stream.html",
          "Content-Type": "application/x-www-form-urlencoded"
        },
        // body に tab パラメータを追加する
        // encodeURIComponent: URL に使えない文字（スペースなど）をエンコードする
        // 例: "tab=must" のような文字列を送信する
        body: `tab=${encodeURIComponent(currentTab)}`
      })

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      } else {
        console.error(`タスク更新に失敗しました。ステータス: ${response.status}`)
        checkbox.checked = !checkbox.checked
      }
    } catch (error) {
      console.error("ネットワークエラーが発生しました:", error)
      checkbox.checked = !checkbox.checked
    }
  }
}
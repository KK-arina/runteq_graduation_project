// app/javascript/controllers/habit_sort_controller.js
// =============================================================
// Stimulus コントローラー: 習慣一覧の Drag & Drop 並び替えを管理する
// （B-6 完成版）
// =============================================================

import { Controller } from "@hotwired/stimulus"
import Sortable from "Sortable"

export default class extends Controller {
  // ===========================================================
  // Values の定義
  // ===========================================================
  // sortUrl: String
  //   data-habit-sort-sort-url-value 属性から取得した PATCH リクエストの送信先 URL。
  //
  // locked: Boolean
  //   data-habit-sort-locked-value 属性から取得したロック状態。
  //   true のとき SortableJS を初期化しない（並び替えを無効化）。
  static values = {
    sortUrl: String,
    locked:  Boolean
  }

  // ===========================================================
  // connect（Stimulus ライフサイクル）
  // ===========================================================
  // コントローラーが HTML 要素に紐付けられたとき自動で呼ばれる。
  connect() {
    // PDCAロック中は SortableJS を初期化しない。
    // ERB 側でドラッグハンドルを非表示にしているが、
    // JS レイヤーでも二重に防止する。
    if (this.lockedValue) return

    this.sortable = Sortable.create(this.element, {
      // animation: 並び替えアニメーションの時間（ミリ秒）
      animation: 150,

      // handle: この属性を持つ要素だけがドラッグの「持ち手」になる。
      // チェックボックスや数値入力を誤ってドラッグしないための設定。
      handle: "[data-sort-handle]",

      // ghostClass: ドラッグ中に元の位置に残る「影」のクラス。
      ghostClass: "opacity-50",

      // chosenClass: ドラッグ中に掴んでいるカードに付けるクラス。
      chosenClass: "ring-2",

      // forceFallback: true
      //   ネイティブ HTML5 ドラッグ&ドロップの代わりに
      //   SortableJS 独自の実装を使う。
      //   display: grid のコンテナで確実に動作させるために必要。
      forceFallback: true,

      // fallbackClass: forceFallback 時にドラッグ中の要素に付けるクラス。
      fallbackClass: "opacity-75",

      // onEnd: ドラッグが終わったとき（指を離したとき）に呼ぶ関数。
      // アロー関数で this を Stimulus コントローラーに固定する。
      onEnd: (evt) => {
        this.updateOrder()
      }
    })
  }

  // ===========================================================
  // disconnect（Stimulus ライフサイクル）
  // ===========================================================
  // コントローラーが HTML 要素から切り離されたとき自動で呼ばれる。
  // SortableJS インスタンスを破棄してメモリリークを防ぐ。
  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
    }
  }

  // ===========================================================
  // updateOrder（並び替え後にサーバーへ送信する）
  // ===========================================================
  // SortableJS が DOM の順序を変更した後、
  // 現在の DOM 上の並び順を取得して PATCH /habits/sort に送信する。
  updateOrder() {
    // data-habit-id 属性を持つ全カードを DOM 順で取得し、
    // 習慣 ID の配列を作る。
    const habitIds = Array.from(
      this.element.querySelectorAll("[data-habit-id]")
    ).map(el => el.dataset.habitId)

    // fetch で PATCH リクエストを送信する。
    // X-CSRF-Token は Rails の CSRF 保護のために必要。
    fetch(this.sortUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify({ habit_ids: habitIds })
    })
    .then(response => {
      if (!response.ok) {
        console.error("並び替えの保存に失敗しました")
      }
    })
    .catch(error => {
      console.error("並び替えリクエストでエラーが発生しました:", error)
    })
  }
}
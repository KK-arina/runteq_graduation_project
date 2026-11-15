// app/javascript/controllers/habit_sort_controller.js
// =============================================================
// Stimulus コントローラー: 習慣一覧の Drag & Drop 並び替えを管理する
// （B-6 完成版）
// =============================================================
//
// 【Lighthouse 対応: SortableJS を「習慣一覧を開いたときだけ」読み込む】
//   以前はこのファイルの一番上で import Sortable from "Sortable" していたため、
//   controllers/index.js（アプリ起動時に全コントローラーを読み込む）経由で、
//   習慣一覧以外のページでも SortableJS（約 24KB）が毎回読み込まれていた。
//   import("Sortable")（動的 import）を connect() の中で呼び、
//   並び替えの要素（data-controller="habit-sort"）が画面に出たときだけ読み込む。
//   config/importmap.rb でも preload: false にして、全ページでの先読みをやめている。
// =============================================================

import { Controller } from "@hotwired/stimulus"

// -------------------------------------------------------------
// SortableJS の読み込み（1回だけ行い、2回目以降は使い回す）
// -------------------------------------------------------------
//
// 【sortablePromise をコントローラーの外に置く理由】
//   コントローラーは画面を開くたびに作り直されるが、このファイル（モジュール）の
//   変数はページを読み込み直すまで残る。ここに Promise を保存しておけば、
//   2回目以降に習慣一覧を開いたときは、ファイルを取りに行かずにすぐ使える。
//
// 【module.default を返す理由】
//   sortable.esm.js は「export default Sortable」で本体を書き出している。
//   動的 import はモジュール全体（書き出したものの入れ物）を返すため、
//   本体は .default から取り出す。
let sortablePromise = null

const loadSortable = () => {
  if (!sortablePromise) {
    sortablePromise = import("Sortable")
      .then((module) => module.default)
      .catch((error) => {
        // 読み込みに失敗した場合（Render のスリープ復帰中の通信失敗など）は、
        // 保存した Promise を捨てて、次に開いたときに取り直せるようにする。
        sortablePromise = null
        throw error
      })
  }
  return sortablePromise
}

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
  //
  // 【async にした理由】
  //   SortableJS の読み込み（await loadSortable()）が終わるまで待ってから初期化するため。
  //
  // 【connectId（接続の番号）を使う理由】
  //   読み込みを待っている間に、別のページへ移動したり、Turbo のキャッシュから
  //   同じページが表示し直されたりすることがある。番号が変わっていたら
  //   （＝もう別の接続になっていたら）初期化せずに終わり、二重の初期化を防ぐ。
  async connect() {
    // PDCAロック中は SortableJS を初期化しない（読み込みもしない）。
    // ERB 側でドラッグハンドルを非表示にしているが、
    // JS レイヤーでも二重に防止する。
    if (this.lockedValue) return

    this._connectId = (this._connectId || 0) + 1
    const connectId = this._connectId

    let Sortable
    try {
      Sortable = await loadSortable()
    } catch (error) {
      console.error("並び替えの部品（SortableJS）を読み込めませんでした。ページを再読み込みしてください。", error)
      return
    }

    // 待っている間に別の接続になった、または画面から外れた場合は初期化しない
    if (connectId !== this._connectId || !this.element.isConnected) return

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
    // 接続の番号を進め、読み込み待ちの connect() が初期化しないようにする
    this._connectId = (this._connectId || 0) + 1

    if (this.sortable) {
      this.sortable.destroy()
      // null に戻し、次の接続で古いインスタンスを destroy し直さないようにする
      this.sortable = null
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
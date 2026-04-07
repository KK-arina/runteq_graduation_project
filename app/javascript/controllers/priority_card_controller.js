// app/javascript/controllers/priority_card_controller.js
//
// ==============================================================================
// PriorityCardController（C-1: 優先度カード選択UI）
// ==============================================================================
// 【このファイルの役割】
//   タスク作成フォームの優先度カード（Must/Should/Could）の
//   選択状態をビジュアルで切り替える Stimulus コントローラー。
//
// 【なぜ Tailwind の peer-checked だけでは不十分なのか】
//   peer-checked はラジオボタンが「チェックされた状態」のスタイルを適用するが、
//   「チェックが外れた状態」への自動的な切り替えができない。
//   例: Must を選択 → Should のカードが青のまま残る
//   Stimulus で全カードを一度リセットしてから選択中のカードだけアクティブにすることで
//   この問題を解決する。
//
// 【動作の流れ】
//   1. ページ読み込み時（connect）:
//      現在 checked のラジオに対応するカードをアクティブにする。
//      バリデーションエラー後のフォーム再表示でも選択状態を復元できる。
//   2. ラジオボタン変更時（select）:
//      全カードを非アクティブにしてから、選択中のカードだけアクティブにする。
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // static targets: このコントローラーが参照する DOM 要素を宣言する。
  // 宣言すると this.labelTargets（配列）が自動で使えるようになる。
  // label → data-priority-card-target="label" が付いた要素（各 label タグ）
  // card  → data-priority-card-target="card"  が付いた要素（カードの div）
  static targets = ["label", "card"]

  // connect: コントローラーが DOM に接続されたとき自動で呼ばれる。
  // ページ読み込み・Turbo Drive でのページ遷移時に実行される。
  connect() {
    this.updateCards()
  }

  // select: ラジオボタンの change イベントで呼ばれる。
  // HTML 側に data-action="change->priority-card#select" を付けることで紐付く。
  select() {
    this.updateCards()
  }

  // updateCards: 全カードのスタイルを現在の checked 状態に合わせて更新する。
  // 全カードをリセット → checked のカードだけアクティブ化 の順で処理する。
  updateCards() {
    this.labelTargets.forEach(label => {
      // label 内の radio input を取得する
      const radio = label.querySelector("input[type='radio']")
      // label 内の card div（data-priority-card-target="card"）を取得する
      const card  = label.querySelector("[data-priority-card-target='card']")

      // どちらかが存在しなければスキップする
      if (!radio || !card) return

      // data-active-class に指定したクラス文字列をスペースで分割して配列にする。
      // 例: "border-red-500 bg-red-50" → ["border-red-500", "bg-red-50"]
      // filter(Boolean) で空文字を除去する（スペースが余分にある場合の対策）。
      const activeClasses   = (card.dataset.activeClass   || "").split(" ").filter(Boolean)
      const inactiveClasses = (card.dataset.inactiveClass || "").split(" ").filter(Boolean)

      if (radio.checked) {
        // 選択中: アクティブクラスを追加・非アクティブクラスを削除
        card.classList.add(...activeClasses)
        card.classList.remove(...inactiveClasses)
      } else {
        // 非選択: 非アクティブクラスを追加・アクティブクラスを削除
        card.classList.remove(...activeClasses)
        card.classList.add(...inactiveClasses)
      }
    })
  }
}
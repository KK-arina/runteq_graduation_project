// app/javascript/controllers/mood_rating_controller.js
//
// =============================================================================
// E-1: 気分スコア（星評価UI）Stimulus コントローラー
// =============================================================================
//
// 【なぜ inline script ではなく Stimulus を使うのか】
//
//   レビュー指摘を受けて inline script から Stimulus に変更する。
//   inline script には以下の問題がある:
//
//   ① Turbo 遷移で動かない / listener が多重登録される
//      - turbo:load のたびに addEventListener が重複追加される
//      - 遷移を繰り返すと listener がメモリ上に蓄積してメモリリークが起きる
//
//   ② render :new 後に再初期化されない
//      - バリデーションエラーで render :new されたとき
//        inline script は再実行されないため星の状態が壊れる
//
//   ③ CSP（Content Security Policy）に引っかかる可能性がある
//      - 将来 CSP を強化したとき inline script が動かなくなる
//
//   Stimulus を使うことで:
//
//   ① connect() がページ表示のたびに自動実行される（Turbo 対応済み）
//   ② disconnect() でクリーンアップされる（メモリリーク防止）
//   ③ Rails 7 標準構成に統一できる
//   ④ 責務が分離されてテスト・保守がしやすくなる
//
// 【このコントローラーの役割】
//   - ラジオボタンの選択状態に応じて星の色（☆/★ + gray/yellow）を更新する
//   - 選択されたスコアに対応するラベルテキストを更新する
//   - connect() 時に既存の選択状態を反映する（バリデーションエラー後の再描画対応）
//
// 【HTML 側の使い方】
//   <div data-controller="mood-rating">
//     <input type="radio" data-mood-rating-target="radio" value="1" ...>
//     <label data-mood-rating-target="star" data-score="1">☆</label>
//     ...
//     <span data-mood-rating-target="label">選択してください</span>
//   </div>
//
// =============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ============================================================
  // Targets の定義
  // ============================================================
  static targets = [
    // radio: ラジオボタン本体（hidden）
    //        name="weekly_reflection[mood]" の各 input[type=radio]
    "radio",
    // star: 星を表示するラベル要素
    //       data-score 属性にスコア値（1〜5）を持つ
    "star",
    // label: 現在選択中のスコードのテキストラベル
    //        「😊 良い」などを表示する span
    "label"
  ]

  // ============================================================
  // 気分スコアのラベルマップ
  // ============================================================
  //
  // static values として定義することもできるが、
  // 固定の文字列定数なのでクラスプロパティとして定義する。
  // 外部から変更する必要がないため static にする。
  static MOOD_LABELS = {
    1: "😞 とても悪い",
    2: "😕 悪い",
    3: "😐 普通",
    4: "😊 良い",
    5: "😄 とても良い"
  }

  // ============================================================
  // connect() ライフサイクルフック
  // ============================================================
  //
  // Stimulus コントローラーが DOM に接続されたとき（ページ表示・Turbo 遷移後）
  // に自動的に呼ばれる。
  //
  // 【なぜ connect() で update() を呼ぶのか】
  //   バリデーションエラーで render :new されたとき、
  //   @weekly_reflection.mood に値が残っている場合がある。
  //   connect() で update() を呼ぶことで、既存の選択状態を
  //   星のビジュアルに反映できる。
  connect() {
    this.update()
  }

  // ============================================================
  // update メソッド（data-action で呼ばれる）
  // ============================================================
  //
  // 【呼ばれるタイミング】
  //   HTML 側で data-action="change->mood-rating#update" を設定した
  //   ラジオボタンが変更されたとき。
  //
  // 【処理内容】
  //   1. 選択中のラジオボタンを探してスコアを取得する
  //   2. 各 star ターゲットを「選択スコア以下か」で黄色/グレーに更新する
  //   3. label ターゲットのテキストを更新する
  update() {
    // 選択中のラジオボタンを探す
    // find は条件に合う最初の要素を返す（radioTargets は配列）
    const checkedRadio = this.radioTargets.find(radio => radio.checked)

    // 選択スコアを整数で取得する（未選択なら 0）
    // parseInt(string, 基数) の第2引数 10 は「10進数として解釈する」という意味
    // 基数を省略すると "08" などで8進数として解釈されることがあるため明示する
    const selectedScore = checkedRadio
      ? parseInt(checkedRadio.value, 10)
      : 0

    // 各 star ターゲットの表示を更新する
    // index は 0 始まりなので score は index + 1 で1始まりに変換する
    this.starTargets.forEach((star, index) => {
      const score = index + 1

      if (score <= selectedScore) {
        // 選択スコア以下の星 → 塗り星（★）・黄色
        star.textContent = "★"
        star.classList.add("text-yellow-400")
        star.classList.remove("text-gray-300")
      } else {
        // 選択スコアより大きい星 → 空星（☆）・グレー
        star.textContent = "☆"
        star.classList.remove("text-yellow-400")
        star.classList.add("text-gray-300")
      }
    })

    // label ターゲットのテキストを更新する
    // haslabelTarget: label ターゲットが存在する場合のみ処理する
    // （ターゲットが存在しない状態で labelTarget を参照するとエラーになる）
    if (this.hasLabelTarget) {
      if (selectedScore > 0) {
        // 選択済み → ラベルマップからテキストを取得する
        this.labelTarget.textContent = this.constructor.MOOD_LABELS[selectedScore] || ""
        this.labelTarget.classList.remove("text-gray-400")
        this.labelTarget.classList.add("text-gray-600")
      } else {
        // 未選択 → プレースホルダーテキストを表示する
        this.labelTarget.textContent = "選択してください"
        this.labelTarget.classList.remove("text-gray-600")
        this.labelTarget.classList.add("text-gray-400")
      }
    }
  }

  // ============================================================
  // reset メソッド（リセットボタンから呼ばれる）
  // ============================================================
  //
  // 【呼ばれるタイミング】
  //   「リセット」ボタンの data-action="click->mood-rating#reset" から呼ばれる。
  //
  // 【処理内容】
  //   1. すべてのラジオボタンの checked を false にする
  //   2. update() を呼んで星を未選択状態に戻す
  reset() {
    // すべてのラジオボタンを unchecked にする
    this.radioTargets.forEach(radio => {
      radio.checked = false
    })

    // 星の表示を未選択状態に更新する
    this.update()
  }
}

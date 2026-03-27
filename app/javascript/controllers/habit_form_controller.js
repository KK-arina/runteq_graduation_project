// app/javascript/controllers/habit_form_controller.js
// =============================================================
// Stimulus コントローラー: 習慣作成フォームの動的切り替えを管理する
// （B-1: 新規作成・選択ボタンのハイライト修正）
// =============================================================
//
// 【このコントローラーの役割】
//   習慣作成フォームで measurement_type（チェック型/数値型）が変更されたとき、
//   ① ラジオボタンのラベル（カード全体）の見た目を切り替える ← 今回修正
//   ② unit（単位）フィールドの表示/非表示を切り替える
//   ③ weekly_target の max 属性とヒント文を変更する
//
// 【なぜ今回の修正が必要だったか】
//   もともと label タグの「青枠（border-blue-500 bg-blue-50）」は
//   サーバー側の Ruby（ERB）で初期表示時にだけ設定していた。
//   ユーザーがラジオボタンをクリックして切り替えたとき、
//   JavaScript 側でラベルのクラスを更新する処理がなかったため、
//   「クリックしても見た目が変わらない」バグが発生していた。
//
// 【なぜ Stimulus を使うのか】
//   純粋な HTML/CSS だけでは「選択肢が変わったときに別の要素を更新する」
//   という動的な UI を実現できない（JavaScript が必要）。
//   Stimulus は Rails 標準の軽量 JS フレームワークで、
//   「HTML に data 属性を書いて JS と紐付ける」設計が Rails の思想と合っている。
// =============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ===========================================================
  // Targets の定義
  // ===========================================================
  // static targets に定義すると、HTML の data-habit-form-target 属性から
  // 対応する要素を this.XXXTarget（単数）/ this.XXXTargets（複数）で参照できる。
  static targets = [
    "measurementType",  // ラジオボタン（チェック型/数値型の選択）
    "measurementLabel", // ← 追加: ラジオボタンを囲む label 要素（カード全体）
    "unitField",        // unit（単位）入力フィールドのラッパー div
    "weeklyTargetLabel" // 週次目標のヒント文（「1〜7回」を動的に変更する）
  ]

  // ===========================================================
  // connect メソッド（Stimulus のライフサイクルメソッド）
  // ===========================================================
  // 【なぜ connect() が必要なのか】
  //   ページが最初に表示されたとき（またはSPAで画面が切り替わったとき）に
  //   コントローラーが HTML 要素に紐付けられると自動的に呼ばれる。
  //   ここで「初期状態のハイライト」を JS でもセットしておくことで、
  //   ERB での初期レンダリングと JS での動的切り替えが一致する。
  //
  // 【なぜ ERB だけでは不十分なのか】
  //   ERB（Ruby）はサーバー側で HTML を生成するだけなので、
  //   一度ページが表示された後の「クリックによる変化」には対応できない。
  //   JS（Stimulus）がクライアント側でクラスを付け替える必要がある。
  connect() {
    // ページ読み込み時にも toggleUnit を実行して、
    // 現在の選択状態に合わせてラベルのハイライトを設定する。
    this.toggleUnit()
  }

  // ===========================================================
  // toggleUnit メソッド
  // ===========================================================
  // 【呼び出しタイミング】
  //   ① connect() から呼ばれる（ページ読み込み時）
  //   ② data-action="change->habit-form#toggleUnit" が設定されたラジオボタンが
  //      変更されたとき（change イベント発火時）
  //
  // 【処理の流れ】
  //   1. 現在選択されている measurement_type を取得
  //   2. 各ラジオボタンのラベル（カード）のクラスを切り替える（修正箇所）
  //   3. 数値型なら unit フィールドを表示、チェック型なら非表示
  //   4. weekly_target の max と説明文を切り替え
  toggleUnit() {
    // 現在チェックされているラジオボタンの値を取得する。
    // this.measurementTypeTargets → "measurementType" ターゲット全要素の配列
    // .find(radio => radio.checked) → チェックされているものを探す
    // ?.value → チェックされているものの値（"check_type" または "numeric_type"）
    //            ?. は「見つからなかった場合に undefined を返す」安全演算子
    const selectedType = this.measurementTypeTargets.find(radio => radio.checked)?.value

    const isNumeric = selectedType === "numeric_type"

    // ── ①【修正箇所】ラジオボタンのラベル（カード全体）のハイライトを切り替える ──
    //
    // 【なぜこの処理が必要なのか】
    //   ラジオボタン自体は <input type="radio" class="sr-only"> で非表示にしており、
    //   代わりに label タグ全体をカード風のボタンとして見せている。
    //   ユーザーが「数値型」カードをクリックすると：
    //     - ラジオボタンの checked 状態は変わる（ブラウザが自動で処理）
    //     - しかし label の CSS クラス（青枠など）は自動では変わらない
    //   そのため JS で明示的にクラスを付け替える必要がある。
    //
    // 【処理の詳細】
    //   this.measurementLabelTargets → "measurementLabel" ターゲット全要素の配列
    //   .forEach でラベルを1つずつ処理する。
    //   各ラベルに対応するラジオボタンが選択中かどうかで、
    //   クラスを「選択中スタイル」か「非選択スタイル」に切り替える。
    this.measurementLabelTargets.forEach(label => {
      // このラベル内にあるラジオボタンを取得する
      // querySelector は「この label の中で最初に見つかった input 要素」を返す
      const radio = label.querySelector("input[type='radio']")

      if (radio && radio.checked) {
        // 選択中のラベル: 青枠・青背景を付ける
        //
        // classList.remove: 既存の「非選択」クラスを取り除く
        // classList.add:    「選択中」クラスを追加する
        //
        // 【なぜ remove してから add するのか】
        //   直接 className = "..." と書くと既存の他のクラスが全部消えてしまう。
        //   remove/add を使うことで「目的のクラスだけを変更」できる。
        label.classList.remove("border-gray-200", "hover:border-gray-300")
        label.classList.add("border-blue-500", "bg-blue-50")
      } else {
        // 非選択のラベル: デフォルト（グレー枠）に戻す
        label.classList.remove("border-blue-500", "bg-blue-50")
        label.classList.add("border-gray-200", "hover:border-gray-300")
      }
    })
    // ────────────────────────────────────────────────────────────────────────

    // ── ② unit フィールドの表示/非表示を切り替える ──────────────────────────
    // hidden 属性を追加/削除することで表示を切り替える。
    // display:none を直接操作するよりも semantic（意味的）な方法。
    if (isNumeric) {
      // 数値型: unit フィールドを表示する
      this.unitFieldTarget.removeAttribute("hidden")
    } else {
      // チェック型: unit フィールドを非表示にする
      this.unitFieldTarget.setAttribute("hidden", "")

      // チェック型に切り替えたときは unit の値をクリアする。
      // 数値型で入力した単位（例: "分"）が残ったまま保存されないようにする。
      const unitInput = this.unitFieldTarget.querySelector("input")
      if (unitInput) unitInput.value = ""
    }

    // ── ③ weekly_target のヒント文を切り替える ─────────────────────────────
    // hasWeeklyTargetLabelTarget: "weeklyTargetLabel" ターゲットが存在するか確認
    // （存在しない場合にエラーが出ないよう、存在チェックを先に行う）
    if (this.hasWeeklyTargetLabelTarget) {
      if (isNumeric) {
        // 数値型: 7を超える値も設定できる（例: 150分/週）
        this.weeklyTargetLabelTarget.textContent = "（単位: 1以上の数値）"
      } else {
        // チェック型: 最大7日（週7日が上限）
        this.weeklyTargetLabelTarget.textContent = "（1〜7回）"
      }
    }

    // ── ④ weekly_target の max 属性を動的に変更する ─────────────────────────
    // this.element → このコントローラーが紐付いている最上位の HTML 要素（form タグ）
    // querySelector で form の中から週次目標の input を探す
    const weeklyTargetInput = this.element.querySelector("input[name='habit[weekly_target]']")
    if (weeklyTargetInput) {
      if (isNumeric) {
        // 数値型では max 制限を外す（大きな数値目標を設定できるようにする）
        weeklyTargetInput.removeAttribute("max")
      } else {
        // チェック型では max=7 に戻す（週7日が上限）
        weeklyTargetInput.setAttribute("max", "7")
      }
    }
  }
}

// app/javascript/controllers/habit_form_controller.js
// =============================================================
// Stimulus コントローラー: 習慣作成フォームの動的切り替えを管理する
// （B-6: カラー・アイコン選択処理を追加、レビュー修正適用）
// =============================================================
//
// 【B-6 レビュー対応での修正内容】
//
//   ① syncInitialState() を新規追加（初期状態をJSに統一）
//      修正前:
//        ERB 側で "ring-2 ring-offset-2 ring-gray-800 scale-110" クラスを
//        条件分岐で付与していた（サーバー側での静的なクラス付与）。
//        バリデーションエラー後の再表示時に、
//        見た目（ERBのクラス）と hidden input の value がズレる可能性があった。
//      修正後:
//        connect() 内で syncInitialState() を呼び、
//        hidden input の現在値を基準にして選択状態を JS 側で一元管理する。
//        ERB 側の条件分岐は不要になる（削除済み）。
//
//   ② selectColor() / selectIcon() の hover クラス操作を削除
//      修正前:
//        swatch.classList.add("hover:scale-110") のように
//        Tailwind の hover: 擬似クラスを JS で動的に追加していた。
//      修正後:
//        hover: クラスは HTML（ERB）側に常に付与しておき、
//        JS では ring-2 等の「選択中スタイル」の add/remove のみ行う。
//      理由:
//        Tailwind は使用クラスをビルド時に静的解析する。
//        classList.add("hover:scale-110") のように JS から動的に追加した
//        クラスはビルド対象として検出されない可能性があり、
//        本番ビルドで CSS が生成されずスタイルが壊れるリスクがある。
//        hover: クラスは HTML に直接書くことで確実にビルド対象になる。
//
//   ③ ロック中は habit-sort コントローラーを data-controller に付与しない
//      → これは習慣一覧ビュー（habits/index.html.erb）側で対応する。

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ===========================================================
  // Targets の定義
  // ===========================================================
  static targets = [
    "measurementType",
    "measurementLabel",
    "unitField",
    "weeklyTargetLabel",
    "colorInput",
    "colorSwatch",
    "iconInput",
    "iconButton"
  ]

  // ===========================================================
  // connect（ライフサイクル）
  // ===========================================================
  // コントローラーが HTML 要素に紐付けられたとき自動で呼ばれる。
  // ① 測定タイプの初期表示を同期する
  // ② カラー・アイコンの選択状態を hidden input の値から復元する
  connect() {
    this.toggleUnit()
    // syncInitialState を呼ぶことで、
    // バリデーションエラー後の再表示でも
    // hidden input の値に基づいた正しい選択状態が表示される。
    this.syncInitialState()
  }

  // ===========================================================
  // syncInitialState（B-6 レビュー修正: 新規追加）
  // ===========================================================
  // 【役割】
  //   ページ読み込み時（または Turbo 遷移後）に
  //   hidden input の現在値を読み取って、
  //   対応するスウォッチ・アイコンボタンに「選択中」スタイルを付ける。
  //
  // 【なぜ ERB の条件分岐を使わないのか】
  //   ERB で "ring-2 ring-offset-2 ring-gray-800 scale-110" を条件付与する方法は、
  //   ページ初期表示では正しく動くが、
  //   バリデーションエラー後の再レンダリング時に
  //   params の値と hidden input の value がズレると
  //   見た目と実際の送信値が一致しなくなる。
  //   JS で hidden input の値を直接読んで同期することで
  //   常に「表示されている選択 = 送信される値」を保証できる。
  syncInitialState() {
    // ── カラーの初期選択を同期する ──────────────────────────────
    // hasColorInputTarget: colorInput ターゲットが存在するか確認する。
    // フォーム以外のページでこのコントローラーが呼ばれた場合のエラーを防ぐ。
    if (this.hasColorInputTarget) {
      const currentColor = this.colorInputTarget.value

      this.colorSwatchTargets.forEach(swatch => {
        if (swatch.dataset.colorValue === currentColor) {
          // 選択中のスウォッチに ring を付ける
          swatch.classList.add("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
        } else {
          // 非選択のスウォッチから ring を外す
          swatch.classList.remove("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
        }
      })
    }

    // ── アイコンの初期選択を同期する ──────────────────────────────
    if (this.hasIconInputTarget) {
      const currentIcon = this.iconInputTarget.value

      this.iconButtonTargets.forEach(btn => {
        if (btn.dataset.iconValue === currentIcon) {
          btn.classList.add("border-blue-500", "bg-blue-50", "scale-110")
          btn.classList.remove("border-gray-200")
        } else {
          btn.classList.remove("border-blue-500", "bg-blue-50", "scale-110")
          btn.classList.add("border-gray-200")
        }
      })
    }
  }

  // ===========================================================
  // toggleUnit（変更なし）
  // ===========================================================
  toggleUnit() {
    const selectedType = this.measurementTypeTargets.find(radio => radio.checked)?.value
    const isNumeric = selectedType === "numeric_type"

    this.measurementLabelTargets.forEach(label => {
      const radio = label.querySelector("input[type='radio']")
      if (radio && radio.checked) {
        label.classList.remove("border-gray-200", "hover:border-gray-300")
        label.classList.add("border-blue-500", "bg-blue-50")
      } else {
        label.classList.remove("border-blue-500", "bg-blue-50")
        label.classList.add("border-gray-200", "hover:border-gray-300")
      }
    })

    if (isNumeric) {
      this.unitFieldTarget.removeAttribute("hidden")
    } else {
      this.unitFieldTarget.setAttribute("hidden", "")
      const unitInput = this.unitFieldTarget.querySelector("input")
      if (unitInput) unitInput.value = ""
    }

    if (this.hasWeeklyTargetLabelTarget) {
      this.weeklyTargetLabelTarget.textContent = isNumeric
        ? "（単位: 1以上の数値）"
        : "（1〜7回）"
    }

    const weeklyTargetInput = this.element.querySelector("input[name='habit[weekly_target]']")
    if (weeklyTargetInput) {
      if (isNumeric) {
        weeklyTargetInput.removeAttribute("max")
      } else {
        weeklyTargetInput.setAttribute("max", "7")
      }
    }
  }

  // ===========================================================
  // selectColor（B-6: レビュー修正適用）
  // ===========================================================
  // 【修正内容】
  //   hover クラスの classList 操作を削除した。
  //   hover:scale-110 は各スウォッチボタンの HTML クラスに常に記述しておく。
  //   JS では ring（選択枠）の add/remove のみ行う。
  selectColor(event) {
    const button = event.currentTarget
    const color = button.dataset.colorValue

    // hidden input の値を更新する（フォーム送信時にこの値が Rails に届く）
    this.colorInputTarget.value = color

    // ── 全スウォッチから「選択中」スタイルを外す ──────────────────
    // 【修正】hover:scale-110 の classList 操作を削除。
    // hover クラスは HTML に書いてあるので JS では触らない。
    this.colorSwatchTargets.forEach(swatch => {
      swatch.classList.remove("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
    })

    // ── クリックされたスウォッチに「選択中」スタイルを付ける ──────
    button.classList.add("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
  }

  // ===========================================================
  // selectIcon（B-6: レビュー修正適用）
  // ===========================================================
  // 【修正内容】
  //   hover クラスの classList 操作を削除した。
  //   hover:border-blue-300 / hover:bg-blue-50 は HTML クラスに常に記述。
  //   JS では border-blue-500 等の「選択中スタイル」の add/remove のみ行う。
  selectIcon(event) {
    const button = event.currentTarget
    const icon = button.dataset.iconValue

    this.iconInputTarget.value = icon

    // ── 全アイコンボタンから「選択中」スタイルを外す ──────────────
    // 【修正】hover クラスの操作を削除。
    this.iconButtonTargets.forEach(btn => {
      btn.classList.remove("border-blue-500", "bg-blue-50", "scale-110")
      btn.classList.add("border-gray-200")
    })

    // ── クリックされたボタンに「選択中」スタイルを付ける ──────────
    button.classList.remove("border-gray-200")
    button.classList.add("border-blue-500", "bg-blue-50", "scale-110")
  }
}
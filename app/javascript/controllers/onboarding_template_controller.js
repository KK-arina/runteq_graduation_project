// app/javascript/controllers/onboarding_template_controller.js
//
// ==============================================================================
// OnboardingTemplateController（H-5: オンボーディング習慣テンプレート選択）
// ==============================================================================
//
// 【担当する機能】
//   ① タブ切り替え（テンプレート選択 ↔ 手入力）
//   ② カテゴリフィルタリング（全件 / 健康 / フィットネス / 学習 / マインド）
//   ③ テンプレート選択 → フォーム自動入力
//   ④ habit-form コントローラーとのイベント連携
//
// 【habit-form コントローラーとの連携方法】
//   テンプレート選択後に measurement_type ラジオボタンを変更する際、
//   radio.dispatchEvent(new Event("change", { bubbles: true })) で
//   change イベントを手動発火する。
//   これにより habit-form の toggleUnit() が自動で呼ばれ、
//   unit フィールドの表示/非表示が切り替わる。
//   直接メソッドを呼ぶのではなくイベント経由にする理由:
//   2コントローラーを疎結合に保つため。
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ============================================================
  // static targets
  // ============================================================
  // 各ターゲットの役割:
  //   tabTemplate         : 「テンプレートから選ぶ」タブボタン
  //   tabManual           : 「自分で入力する」タブボタン
  //   panelTemplate       : テンプレートタブのコンテンツ領域
  //   panelManual         : 手入力タブのコンテンツ領域
  //   categoryButton      : カテゴリフィルタボタン群（複数）
  //   templateCard        : テンプレートカード（複数）
  //   selectedBadge       : 選択中の ✓ バッジ（カード内、複数）
  //   nameInput           : 習慣名の入力フィールド
  //   unitInput           : 単位の入力フィールド
  //   weeklyTargetInput   : 週次目標の入力フィールド
  //   measurementTypeRadio: 記録タイプのラジオボタン（複数）
  static targets = [
    "tabTemplate",
    "tabManual",
    "panelTemplate",
    "panelManual",
    "categoryButton",
    "templateCard",
    "selectedBadge",
    "nameInput",
    "unitInput",
    "weeklyTargetInput",
    "measurementTypeRadio"
  ]

  // ============================================================
  // connect()
  // ============================================================
  // Stimulus ライフサイクル。DOM に接続されたとき自動で呼ばれる。
  // 内部状態を初期化する。
  connect() {
    this._selectedCard = null      // 現在選択中のカード要素（null = 未選択）
    this._currentCategory = "all"  // 現在選択中のカテゴリ
  }

  // ============================================================
  // switchToTemplate(): 「テンプレートから選ぶ」タブに切り替える
  // ============================================================
  switchToTemplate() {
    this._setTabActive(this.tabTemplateTarget, true)
    this._setTabActive(this.tabManualTarget, false)
    this.tabTemplateTarget.setAttribute("aria-selected", "true")
    this.tabManualTarget.setAttribute("aria-selected", "false")
    this.panelTemplateTarget.removeAttribute("hidden")
    this.panelManualTarget.setAttribute("hidden", "")
  }

  // ============================================================
  // switchToManual(): 「自分で入力する」タブに切り替える
  // ============================================================
  switchToManual() {
    this._setTabActive(this.tabTemplateTarget, false)
    this._setTabActive(this.tabManualTarget, true)
    this.tabTemplateTarget.setAttribute("aria-selected", "false")
    this.tabManualTarget.setAttribute("aria-selected", "true")
    this.panelTemplateTarget.setAttribute("hidden", "")
    this.panelManualTarget.removeAttribute("hidden")
  }

  // ============================================================
  // filterByCategory(event): カテゴリフィルタボタンがクリックされたとき
  // ============================================================
  // 選択したカテゴリのカードだけを表示し、他を非表示にする。
  // "all" なら全件表示。
  filterByCategory(event) {
    const selectedCategory = event.currentTarget.dataset.category
    this._currentCategory = selectedCategory

    // フィルタボタンのアクティブ状態を更新する
    this.categoryButtonTargets.forEach(button => {
      this._setCategoryButtonActive(
        button,
        button.dataset.category === selectedCategory
      )
    })

    // テンプレートカードの表示/非表示を切り替える
    // HTML 標準の hidden 属性を使う（Tailwind の hidden クラスより確実）
    this.templateCardTargets.forEach(card => {
      const shouldShow =
        selectedCategory === "all" || card.dataset.category === selectedCategory
      if (shouldShow) {
        card.removeAttribute("hidden")
      } else {
        card.setAttribute("hidden", "")
      }
    })
  }

  // ============================================================
  // selectTemplate(event): テンプレートカードがクリックされたとき
  // ============================================================
  // カードの data-template-* 属性を読み取り、フォームに自動入力する。
  // その後 change イベントを発火して habit-form の toggleUnit() を呼ぶ。
  selectTemplate(event) {
    const card = event.currentTarget

    // data-template-* からテンプレートデータを取得する
    const name            = card.dataset.templateName
    const measurementType = card.dataset.templateMeasurementType
    const unit            = card.dataset.templateUnit
    const weeklyTarget    = card.dataset.templateWeeklyTarget

    // フォームに値を自動入力する
    if (this.hasNameInputTarget) {
      this.nameInputTarget.value = name
    }
    if (this.hasUnitInputTarget) {
      this.unitInputTarget.value = unit || ""
    }
    if (this.hasWeeklyTargetInputTarget) {
      this.weeklyTargetInputTarget.value = weeklyTarget
    }

    // measurement_type ラジオボタンを切り替えて change イベントを発火する
    // 発火することで habit-form#toggleUnit が自動で呼ばれ、
    // unit フィールドの表示/非表示が切り替わる
    this.measurementTypeRadioTargets.forEach(radio => {
      if (radio.value === measurementType) {
        radio.checked = true
        // bubbles: true でイベントを親要素に伝播させる
        // これにより data-action="change->habit-form#toggleUnit" が反応する
        radio.dispatchEvent(new Event("change", { bubbles: true }))
      }
    })

    // 選択状態のビジュアルを更新する
    this._deselectAllCards()
    this._selectCard(card)
    this._selectedCard = card
  }

  // ============================================================
  // onMeasurementTypeChange(): ユーザーが手動でラジオボタンを変更したとき
  // ============================================================
  // テンプレートの選択状態をリセットする。
  // テンプレート選択後に手動でタイプを変えると「テンプレートのタイプ」と
  // 「現在の選択タイプ」が不一致になるため、選択状態をクリアする。
  onMeasurementTypeChange() {
    this._deselectAllCards()
    this._selectedCard = null
  }

  // ============================================================
  // Private メソッド
  // ============================================================

  // _setTabActive: タブボタンのスタイルを切り替える
  _setTabActive(tabButton, isActive) {
    if (isActive) {
      tabButton.classList.add("bg-white", "text-blue-600", "border-b-2", "border-blue-600")
      tabButton.classList.remove("text-gray-500", "hover:text-gray-700")
    } else {
      tabButton.classList.remove("bg-white", "text-blue-600", "border-b-2", "border-blue-600")
      tabButton.classList.add("text-gray-500", "hover:text-gray-700")
    }
  }

  // _setCategoryButtonActive: カテゴリフィルタボタンのスタイルを切り替える
  _setCategoryButtonActive(button, isActive) {
    if (isActive) {
      button.classList.add("bg-blue-600", "text-white", "border-blue-600")
      button.classList.remove("bg-white", "text-gray-600", "border-gray-300",
                              "hover:border-blue-400", "hover:text-blue-600")
    } else {
      button.classList.remove("bg-blue-600", "text-white", "border-blue-600")
      button.classList.add("bg-white", "text-gray-600", "border-gray-300",
                           "hover:border-blue-400", "hover:text-blue-600")
    }
  }

  // _selectCard: 指定カードを選択状態にする（青枠・✓バッジ表示）
  // querySelector を使う理由:
  //   selectedBadgeTargets はスコープ全体の配列のため、
  //   「このカード内の selectedBadge」は querySelector で個別取得する。
  _selectCard(card) {
    card.classList.add("border-blue-500", "bg-blue-50", "shadow-sm")
    card.classList.remove("border-gray-200", "hover:border-blue-400", "hover:bg-blue-50")
    const badge = card.querySelector('[data-onboarding-template-target="selectedBadge"]')
    if (badge) {
      badge.classList.remove("hidden")
    }
  }

  // _deselectAllCards: 全カードを非選択状態に戻す
  _deselectAllCards() {
    this.templateCardTargets.forEach(card => {
      card.classList.remove("border-blue-500", "bg-blue-50", "shadow-sm")
      card.classList.add("border-gray-200", "hover:border-blue-400", "hover:bg-blue-50")
      const badge = card.querySelector('[data-onboarding-template-target="selectedBadge"]')
      if (badge) {
        badge.classList.add("hidden")
      }
    })
  }
}
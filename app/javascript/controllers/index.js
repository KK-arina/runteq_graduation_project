// app/javascript/controllers/index.js
//
// =============================================================================
// Stimulus コントローラーの登録（手動登録方式）
// =============================================================================
//
// 【import の書き方: "controllers/xxx_controller"（importmap のキー）を使う】
//   以前は import ... from "./xxx_controller"（相対パス）と書いていた。
//   相対パスは importmap（読み込み先の一覧）を通らず、ブラウザが
//   /assets/controllers/xxx_controller（ハッシュ無しの URL）を直接取りに行く。
//   一方、javascript_importmap_tags は <head> で
//   /assets/controllers/xxx_controller-ハッシュ.js を先読み（modulepreload）している。
//   その結果、全コントローラーが「先読みしたハッシュ付き」と「実際に使うハッシュ無し」の
//   2回ずつダウンロードされ、ハッシュ無しのほうは長期キャッシュも効かなかった。
//
//   config/importmap.rb の pin_all_from "app/javascript/controllers", under: "controllers" は、
//   各ファイルに "controllers/ファイル名" というキーを作る。
//   import でこのキーを書けば、importmap がハッシュ付きの URL に変換するため、
//   先読みしたファイルがそのまま使われ、1回のダウンロードで済む。
//
// 【新しいコントローラーを追加するとき】
//   1. app/javascript/controllers/xxx_controller.js を作る
//   2. このファイルに次の2行を追加する（"./" ではなく "controllers/" で書く）
//        import XxxController from "controllers/xxx_controller"
//        application.register("xxx", XxxController)
//   test/integration/stimulus_controller_imports_test.rb が、
//   相対パスの import が残っていないかを確認している。
// =============================================================================

import { application } from "controllers/application"

import AiAnalysisPollingController from "controllers/ai_analysis_polling_controller"
application.register("ai-analysis-polling", AiAnalysisPollingController)

import AiLimitModalController from "controllers/ai_limit_modal_controller"
application.register("ai-limit-modal", AiLimitModalController)

import AiProposalModalController from "controllers/ai_proposal_modal_controller"
application.register("ai-proposal-modal", AiProposalModalController)

import AiThrottleController from "controllers/ai_throttle_controller"
application.register("ai-throttle", AiThrottleController)

import AlarmToggleController from "controllers/alarm_toggle_controller"
application.register("alarm-toggle", AlarmToggleController)

import CrisisInterventionController from "controllers/crisis_intervention_controller"
application.register("crisis-intervention", CrisisInterventionController)

import DeactivateModalController from "controllers/deactivate_modal_controller"
application.register("deactivate-modal", DeactivateModalController)

import FlashController from "controllers/flash_controller"
application.register("flash", FlashController)

import FormSubmitController from "controllers/form_submit_controller"
application.register("form-submit", FormSubmitController)

import HabitCheckboxController from "controllers/habit_checkbox_controller"
application.register("habit-checkbox", HabitCheckboxController)

import HabitFormController from "controllers/habit_form_controller"
application.register("habit-form", HabitFormController)

import HabitMenuController from "controllers/habit_menu_controller"
application.register("habit-menu", HabitMenuController)

import HabitRecordController from "controllers/habit_record_controller"
application.register("habit-record", HabitRecordController)

import HabitSortController from "controllers/habit_sort_controller"
application.register("habit-sort", HabitSortController)

import HelloController from "controllers/hello_controller"
application.register("hello", HelloController)

import MobileMenuController from "controllers/mobile_menu_controller"
application.register("mobile-menu", MobileMenuController)

import MoodRatingController from "controllers/mood_rating_controller"
application.register("mood-rating", MoodRatingController)

import NotificationLimitController from "controllers/notification_limit_controller"
application.register("notification-limit", NotificationLimitController)

// G-3 修正: 通知全般マスタースイッチの連動コントローラー
import NotificationMasterController from "controllers/notification_master_controller"
application.register("notification-master", NotificationMasterController)

import PriorityCardController from "controllers/priority_card_controller"
application.register("priority-card", PriorityCardController)

// G-4 追加: お休みモード確認モーダルコントローラー
import RestModeModalController from "controllers/rest_mode_modal_controller"
application.register("rest-mode-modal", RestModeModalController)

// G-6 追加: 設定ページのプロフィール編集インライン制御コントローラー
// 【なぜ手動登録するのか】
//   stimulus:manifest:update は自動生成だが、
//   ファイル追加後に実行し忘れることがある。
//   明示的に登録することで確実に動作する。
import SettingsProfileController from "controllers/settings_profile_controller"
application.register("settings-profile", SettingsProfileController)

import TaskMenuController from "controllers/task_menu_controller"
application.register("task-menu", TaskMenuController)

import TaskToggleController from "controllers/task_toggle_controller"
application.register("task-toggle", TaskToggleController)

import TermsAgreementController from "controllers/terms_agreement_controller"
application.register("terms-agreement", TermsAgreementController)

import VoiceInputController from "controllers/voice_input_controller"
application.register("voice-input", VoiceInputController)

// G-7 追加: バナーを×ボタンで非表示にする汎用コントローラー
// 【なぜ手動登録するのか】
//   stimulus:manifest:update は自動生成だが、
//   ファイル追加後に実行し忘れることがある。
//   明示的に登録することで確実に動作する。
import DismissibleController from "controllers/dismissible_controller"
application.register("dismissible", DismissibleController)

// H-4 追加: グラフ・進捗分析ページのChart.js描画コントローラー
// 【なぜ手動登録するのか】
//   stimulus:manifest:update は自動生成だが、
//   ファイル追加後に実行し忘れることがある。
//   明示的に登録することで確実に動作する。
// 【Lighthouse 対応】
//   このコントローラー自体（約 11KB）は全ページで読み込むが、
//   chart.js 本体はグラフのページを開いたときだけ import("chart.js") で読み込む。
import AnalyticsChartController from "controllers/analytics_chart_controller"
application.register("analytics-chart", AnalyticsChartController)

// H-5追加: オンボーディング習慣テンプレート選択コントローラー
import OnboardingTemplateController from "controllers/onboarding_template_controller"
application.register("onboarding-template", OnboardingTemplateController)

// ログイン保持追加: ログイン画面の「ログインしたままにする」連携コントローラー
// 【役割】
//   チェックボックスの状態を Google / LINE ボタンのフォームの送信先 URL に
//   ?remember_me=1 / 0 として反映する（OmniAuth がコールバックまで引き継ぐ）。
// 【登録名 "remember-me" について】
//   ビュー側の data-controller="remember-me" / data-remember-me-target と一致させる。
//   ここの名前とビューの名前がずれると、エラーにならずに何も動かないので注意。
// 【なぜ手動登録するのか】
//   このファイルは手動登録方式のため、新しいコントローラーは
//   ここに import と register を追加しないと読み込まれない。
import RememberMeController from "controllers/remember_me_controller"
application.register("remember-me", RememberMeController)

// ホーム画面に追加（PWA）追加: 端末に合わせて「ホーム画面に追加」の案内を出し分けるコントローラー
// 【役割】
//   設定ページの案内カードと、ログイン画面の注意書き（ホーム画面から開いたときだけ表示）で使う。
//   Chrome / Edge の「インストールできます」の合図（beforeinstallprompt）は、
//   このファイルがアプリ起動時に読み込まれた時点で受け取り始める。
// 【登録名 "pwa-guide" について】
//   ビュー側の data-controller="pwa-guide" / data-pwa-guide-target と一致させる。
// 【なぜ手動登録するのか】
//   このファイルは手動登録方式のため、新しいコントローラーは
//   ここに import と register を追加しないと読み込まれない。
import PwaGuideController from "controllers/pwa_guide_controller"
application.register("pwa-guide", PwaGuideController)

// ホーム画面に追加（PWA）追加: ダッシュボードの「ホーム画面に追加」バナーを ✕ で閉じるコントローラー
// 【役割】
//   ✕ で閉じたことをブラウザの localStorage に記録し、次からは表示しない（サーバーには何も送らない）。
// 【登録名 "install-banner" について】
//   ビュー側の data-controller="install-banner" / data-action="install-banner#dismiss" と一致させる。
// 【なぜ手動登録するのか】
//   このファイルは手動登録方式のため、新しいコントローラーは
//   ここに import と register を追加しないと読み込まれない。
import InstallBannerController from "controllers/install_banner_controller"
application.register("install-banner", InstallBannerController)

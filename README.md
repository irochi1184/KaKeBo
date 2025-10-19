# KaKeBo
**日々の支出を10秒で記録し、月末に迷わず振り返れるようにする iOS26 対応の家計簿アプリ**

SwiftUI × AppGroup × WidgetKit × UserNotifications を活用し、  
「高速入力 × 自動集計 × 見やすいカレンダー × 通知連携」を実現したモダンな家計簿アプリです。

---

## アプリ概要

- **プラットフォーム**：iOS 17〜（iOS 26 対応）  
- **開発言語**：Swift / SwiftUI  
- **構成**：  
  - MVVM + ObservableObject構成  
  - AppGroupによる共有データ永続化  
  - JSONベースのローカル保存（CoreData未使用）  
  - WidgetKit対応  
  - UserNotificationsでのローカル通知  
- **目的**：「使うほどに記録が習慣化する」UX設計

---

## 主な機能一覧

### 家計簿（Transaction管理）
| 機能 | 説明 |
|------|------|
| 支出・収入の登録 | カテゴリ、金額、日付、メモを10秒で登録 |
| 取引一覧 | 日別・月別の集計を自動計算 |
| 取引編集・削除 | スワイプ操作で簡単に更新・削除可能 |
| パフォーマンス最適化 | JSON DTO変換でI/O負荷を軽減 |
| 自動固定費登録 | 月末または指定日に自動計上される固定費テンプレート |

---

### カレンダー画面（CalendarScreen）
| 機能 | 説明 |
|------|------|
| カレンダー表示 | 1ヶ月ごとの支出・収入を可視化 |
| 日別詳細 | その日の支出・収入、ToDoを一覧表示 |
| 長押し追加 | カレンダー上の日付を長押しで取引登録を開く |
| 日別ToDo | 各日付に紐づくToDo管理（支払日など） |
| ToDoスワイプ削除・編集 | 右スワイプで削除、名称タップで直接編集可能 |
| ToDo自動生成 | 「毎月のToDoテンプレート」から自動作成 |

---

### ToDo管理（TodoStore）
| 機能 | 説明 |
|------|------|
| 日別ToDo | カレンダー上の各日に紐づくToDoを追加 |
| 完了チェック | チェックボックスで完了/未完了を切替 |
| 編集・削除 | 名称タップで編集、スワイプで削除 |
| 期日設定 | 日付ポップアップで期日を簡単に変更 |
| 月跨ぎ反映 | 前月の繰越ToDoを自動移行 |
| 検索・フィルタ | 「未完のみ表示」トグル対応 |

---

### リマインダー（ReminderSettings）
| 機能 | 説明 |
|------|------|
| 通知スケジュール | 毎日 or 毎週（曜日指定）で通知設定可能 |
| 通知メッセージ | タイトル・本文・プレースホルダー対応（例：`{todosToday}`） |
| プレースホルダー挿入チップ | `{todosToday}` `{unloggedToday}` をワンタップで挿入 |
| 通知プレビュー | 実際のデータを差し替えてリアルタイムで表示 |
| テスト送信 | 「紙飛行機」アイコンで即座に通知テスト |
| 権限確認 | 通知が許可されていない場合はアラート表示（設定アプリ誘導付き） |

---

### カテゴリ管理（CategoryListView）
| 機能 | 説明 |
|------|------|
| カテゴリ一覧 | 支出・収入カテゴリをグリッド表示 |
| アイコン選択 | SF Symbolsピッカーでアイコン変更 |
| カラー選択 | パステル50色パレットから選択可能 |
| 並び替え | ドラッグ＆ドロップで順序変更 |
| 削除連動 | カテゴリ削除時、関連する取引も同時削除 |

---

### 固定費管理（FixedExpenseSettingsView）
| 機能 | 説明 |
|------|------|
| 固定費テンプレート | 毎月の定額支出をテンプレート化 |
| 自動計上 | 指定日になると自動的に取引へ登録 |
| 手動登録 | ワンタップでその月の固定費を登録可能 |
| 31日/末日対応 | 月末 or 任意日指定OK（0=月末） |

---

### 設定画面（SettingsView）
| 機能 | 説明 |
|------|------|
| カテゴリ管理への遷移 | カテゴリを個別管理 |
| 固定費管理への遷移 | 毎月の固定費を管理 |
| 毎月ToDo設定 | 定期ToDoテンプレートの設定 |
| リマインダー管理 | 通知の頻度・内容・条件を柔軟に設定 |
| 通知権限チェック | 未許可の場合はアラート表示＋設定画面誘導 |

---

### データ永続化（DataStore / TodoStore）
- AppGroupコンテナ配下に JSON ファイルとして保存  
  - `categories.json`  
  - `transactions.json`  
  - `budgets.json`  
- DTO変換で旧データ互換を維持  
- 初回起動時にシードデータ投入  
- ファイルI/O時に自動Widget更新（`WidgetCenter.shared.reloadAllTimelines()`）

---

### 通知マネージャ（ReminderManager）
| 機能 | 説明 |
|------|------|
| 毎日通知 | 任意の時刻に家計簿リマインダー |
| 毎週通知 | 曜日選択式の繰り返し通知 |
| 毎月ToDo通知 | 期日当日に自動リマインダー送信 |
| テスト通知 | 即時1秒後の通知テスト送信 |
| フォアグラウンド表示対応 | AppDelegateで`willPresent`により前面でもバナー表示可能 |

---

## 画面イメージ

<div align="center">
<img width="360" alt="IMG_8198" src="https://github.com/user-attachments/assets/90753b80-0503-4617-a13d-71695e712d0e" />
<br/>
<img width="360" alt="IMG_8199" src="https://github.com/user-attachments/assets/cad2ca1d-3e85-4176-95de-41402478f65b" />
<br/>
<img width="360" alt="IMG_8200" src="https://github.com/user-attachments/assets/d4894949-ff58-4de6-87ca-93b49b8e0d18" />
<br/>
<img width="360" alt="IMG_8201" src="https://github.com/user-attachments/assets/74e47af3-1b7e-471d-b80e-c155eac5cbdd" />
<br/>
<img width="360" alt="IMG_8202" src="https://github.com/user-attachments/assets/79a5c97e-d819-4770-b10d-06146d2211c0" />
</div>

---

## 技術スタック

- **SwiftUI**：UI構築全般  
- **WidgetKit**：ホーム画面ウィジェット  
- **UserNotifications**：ローカル通知（テスト含む）  
- **AppStorage / UserDefaults**：ユーザー設定の保存  
- **AppGroup Container**：アプリとWidget間のデータ共有  
- **Combine**：@Publishedで双方向データ反映  
- **JSONEncoder / Decoder**：軽量ローカル永続化

---

## 今後の展望
- iCloud同期によるマルチデバイス対応  
- 月次レポートPDF出力  
- ウィジェットから直接登録  
- 家計簿データのAI分析（支出傾向レポート）

---

## ライセンス
MIT License  
© 2025 Kenichiro Arita (irochi)


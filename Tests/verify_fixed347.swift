import Foundation
@main struct Verify347 {
 static func main() {
  let cases: [(String,String,String)] = [
   ("保存しました。","保存済み","保存しました。保存済み"),
   ("保存保留","保存保留：日付を確認","保存保留。保存保留：日付を確認"),
   ("復元しました。","保存済み","復元しました。保存済み"),
   ("保存済み","保存済み","保存済み"),
   ("","保存済み","保存済み"),
   ("保存しました。","","保存しました。"),
   (" 保存しました。 "," 保存済み ","保存しました。保存済み")
  ]
  for (message,status,expected) in cases {
   precondition(CSVHistoryFeedbackPresentation.announcement(message:message,status:status) == expected)
   precondition(CSVHistoryFeedbackPresentation.visibleMessage(message) == message)
  }
  print("FIXED347: \(cases.count * 2) assertions passed")
 }
}

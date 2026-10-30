from pathlib import Path
import subprocess,tempfile,unittest,json,base64
ROOT=Path(__file__).resolve().parents[1]
class LinkTests(unittest.TestCase):
 def test_links(self):
  payload={"v":1,"n":"山田 太郎","s":"東京本店","d":["2026-11-03","2026-11-10","2026-11-03"],"r":"通院"}
  token=base64.urlsafe_b64encode(json.dumps(payload,ensure_ascii=False).encode()).decode().rstrip("=")
  invalid=[]
  for change in [{"v":2},{"d":["2026-02-30"]},{"d":[]},{"n":""},{"d":["2026-1-03"]},{"d":["2201-01-01"]}]:
   data=dict(payload);data.update(change);invalid.append(base64.urlsafe_b64encode(json.dumps(data).encode()).decode().rstrip("="))
  program='''import Foundation
@main struct Runner {
 static func main() throws {
  let token = "TOKEN"
  let link = IncomingLeaveLink.decode(URL(string:"https://facility-manager-phi.vercel.app/hotel-shift/r?openExternalBrowser=1#"+token)!)!
  precondition(link.name=="山田 太郎" && link.storeName=="東京本店" && link.reason=="通院")
  precondition(link.dateKeys==["2026-11-03","2026-11-10"])
  precondition(link.formText.contains("2026-11-03"))
  for scheme in ["hotelshift", "eldiashift"] { precondition(IncomingLeaveLink.decode(URL(string:scheme+"://request#"+token)!)==link) }
  let text="【希望休の申請】\\n名前：山田 太郎\\n▼取り込みリンク\\nhttps://facility-manager-phi.vercel.app/hotel-shift/r?openExternalBrowser=1#"+token
  precondition(IncomingLeaveLink.fromText(text)==link)
  for prefix in ["https://evil.example/hotel-shift/r#","https://facility-manager-phi.vercel.app/hotel-shift/request#","https://facility-manager-phi.vercel.app/hotel-shift/rogue#","http://facility-manager-phi.vercel.app/hotel-shift/r#","https://user@facility-manager-phi.vercel.app/hotel-shift/r#","eldiashift://other#"] { precondition(IncomingLeaveLink.decode(URL(string:prefix+token)!)==nil) }
  for token in INVALID { precondition(IncomingLeaveLink.decode(URL(string:"eldiashift://request#"+token)!)==nil) }
  let old="eyJ2IjoxLCJuIjoiVGVzdCIsImQiOlsiMjAyNi0xMS0wMyJdfQ"
  let minimal=IncomingLeaveLink.decode(URL(string:"eldiashift://request#"+old)!)!
  precondition(minimal.storeName.isEmpty && minimal.reason.isEmpty)
  let loc=HotelLocation(name:"東京本店"), other=HotelLocation(name:"東京別館")
  precondition(IncomingLeaveLink.matchingLocations("東京本店",locations:[loc,other])==[loc])
  precondition(IncomingLeaveLink.matchingLocations("東京本店",locations:[loc,loc]).count==2)
  precondition(IncomingLeaveLink.storeField("名前：Test\\n店舗：東京本店\\n休みたい日：11/3")=="東京本店")
  let form=RequestFormLink.url(storeName:"東京本店 & 休憩室")
  let query=URLComponents(url:form,resolvingAgainstBaseURL:false)!.queryItems!
  precondition(form.host=="facility-manager-phi.vercel.app" && form.path=="/hotel-shift/request")
  precondition(query.first(where:{$0.name=="s"})?.value=="東京本店 & 休憩室")
 }
}
'''.replace("TOKEN",token).replace("INVALID",json.dumps(invalid))
  with tempfile.TemporaryDirectory() as tmp:
   src=Path(tmp)/"Runner.swift";src.write_text(program)
   r=subprocess.run(["swiftc","-parse-as-library","-module-cache-path",tmp+"/cache",str(ROOT/"HOTEL_SHIFT/Models/ShiftModels.swift"),str(src),"-o",tmp+"/test"],capture_output=True,text=True,timeout=60)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([tmp+"/test"],capture_output=True,text=True,timeout=30)
   self.assertEqual(r.returncode,0,r.stderr)
if __name__=="__main__":unittest.main()

import json
import os
import requests
import time

# ==============================================================================
# 1. PASTE THE WEBSITE URL HERE
# ==============================================================================
WEBSITE_URL = "https://johnmarctumulak.com/roblox/"

# ==============================================================================
# 2. PASTE THE JSON FROM ROBLOX STUDIO BELOW
# ==============================================================================
RAW_DATA = """
[{"name":"Avocadini Guffo","anims":[{"id":"91557916868710","type":"Idle"},{"id":"133795603562790","type":"Walk"}]},{"name":"Ballerina Cappuccina","anims":[{"id":"83481340971509","type":"Idle"},{"id":"80405293887127","type":"Walk"}]},{"name":"Ballerino Lololo","anims":[{"id":"119254415468291","type":"Idle"},{"id":"98186521875806","type":"Walk"}]},{"name":"Bambini Crostini","anims":[{"id":"120239081903170","type":"Idle"},{"id":"136726867219912","type":"Walk"}]},{"name":"Bananita Dolphinita","anims":[{"id":"116179514688417","type":"Idle"},{"id":"89461400098972","type":"Walk"}]},{"name":"Bandito Bobritto","anims":[{"id":"122012698939159","type":"Idle"},{"id":"123319785899564","type":"Walk"}]},{"name":"Blueberrinni Octopusini","anims":[{"id":"88166807323914","type":"Idle"},{"id":"138652544517770","type":"Walk"}]},{"name":"Bombardiro Crocodilo","anims":[{"id":"83035400569733","type":"Idle"},{"id":"83035400569733","type":"Walk"}]},{"name":"Bombombini Gusini","anims":[{"id":"72072803799903","type":"Idle"},{"id":"71184576027820","type":"Walk"}]},{"name":"Boneca Ambalabu","anims":[{"id":"126088136737282","type":"Idle"},{"id":"120473765231256","type":"Walk"}]},{"name":"Brainrot God Lucky Block","anims":[{"id":"97941213049282","type":"Idle"},{"id":"97941213049282","type":"Walk"}]},{"name":"Brr Brr Patapim","anims":[{"id":"136384455868563","type":"Idle"},{"id":"82382121122565","type":"Walk"}]},{"name":"Brri Brri Bicus Dicus Bombicus","anims":[{"id":"82488938355382","type":"Idle"},{"id":"128735975658413","type":"Walk"}]},{"name":"Burbaloni Loliloli","anims":[{"id":"93181185790325","type":"Idle"},{"id":"131175428618292","type":"Walk"}]},{"name":"Cacto Hipopotamo","anims":[{"id":"114750709163257","type":"Idle"},{"id":"74245938897726","type":"Walk"}]},{"name":"Cappuccino Assassino","anims":[{"id":"127052216913915","type":"Idle"},{"id":"124408800331802","type":"Walk"}]},{"name":"Cavallo Virtuoso","anims":[{"id":"118455550951606","type":"Idle"},{"id":"84555244808974","type":"Walk"}]},{"name":"Chef Crabracadabra","anims":[{"id":"125651083349040","type":"Idle"},{"id":"81365246982582","type":"Walk"}]},{"name":"Chicleteira Bicicleteira","anims":[{"id":"113321913728770","type":"Idle"},{"id":"92548223831596","type":"Walk"}]},{"name":"Chimpanzini Bananini","anims":[{"id":"126367136269449","type":"Idle"},{"id":"87692095665423","type":"Walk"}]},{"name":"Chimpanzini Spiderini","anims":[{"id":"117686018100268","type":"Idle"},{"id":"114329876014358","type":"Walk"}]},{"name":"Cocofanto Elefanto","anims":[{"id":"100123222426681","type":"Idle"},{"id":"90954091795495","type":"Walk"}]},{"name":"Espresso Signora","anims":[{"id":"99242640090083","type":"Idle"},{"id":"122469950564285","type":"Walk"}]},{"name":"Fluriflura","anims":[{"id":"104940159157522","type":"Idle"},{"id":"137852323685592","type":"Walk"}]},{"name":"Frigo Camelo","anims":[{"id":"129075363254701","type":"Idle"},{"id":"92175692860459","type":"Walk"}]},{"name":"Gangster Footera","anims":[{"id":"88226585718450","type":"Idle"},{"id":"120853920628299","type":"Walk"}]},{"name":"Garama and Madundung","anims":[{"id":"136076007327434","type":"Idle"},{"id":"129661602645449","type":"Walk"}]},{"name":"Gattatino Neonino","anims":[{"id":"136089995715263","type":"Idle"},{"id":"103511838773905","type":"Walk"}]},{"name":"Girafa Celestre","anims":[{"id":"75648385642456","type":"Idle"},{"id":"137154131106273","type":"Walk"}]},{"name":"Glorbo Fruttodrillo","anims":[{"id":"81601005067863","type":"Idle"},{"id":"131290492083037","type":"Walk"}]},{"name":"Gorillo Watermelondrillo","anims":[{"id":"124185153814538","type":"Idle"},{"id":"102196313454402","type":"Walk"}]},{"name":"Graipuss Medussi","anims":[{"id":"96070244184243","type":"Idle"},{"id":"129223146700468","type":"Walk"}]},{"name":"La Grande Combinasion","anims":[{"id":"112980801875781","type":"Idle"},{"id":"100858874355868","type":"Walk"}]},{"name":"La Vacca Saturno Saturnita","anims":[{"id":"97868996676670","type":"Idle"},{"id":"111706640551246","type":"Walk"}]},{"name":"Las Tralaleritas","anims":[{"id":"83538208475602","type":"Idle"},{"id":"128792738487976","type":"Walk"}]},{"name":"Las Vaquitas Saturnitas","anims":[{"id":"134140978010282","type":"Idle"},{"id":"104681441530588","type":"Walk"}]},{"name":"Lionel Cactuseli","anims":[{"id":"130208685044419","type":"Idle"},{"id":"118908650789229","type":"Walk"}]},{"name":"Lirilì Larilà","anims":[{"id":"137502381392673","type":"Idle"},{"id":"138582504788680","type":"Walk"}]},{"name":"Los Crocodillitos","anims":[{"id":"85386972380099","type":"Idle"},{"id":"128656912641127","type":"Walk"}]},{"name":"Los Tralaleritos","anims":[{"id":"83538208475602","type":"Idle"},{"id":"128792738487976","type":"Walk"}]},{"name":"Matteo","anims":[{"id":"119400199944196","type":"Idle"},{"id":"89183268122793","type":"Walk"}]},{"name":"Mythic Lucky Block","anims":[{"id":"97941213049282","type":"Idle"},{"id":"97941213049282","type":"Walk"}]},{"name":"Noobini Pizzanini","anims":[{"id":"118655378652136","type":"Idle"},{"id":"100574740943981","type":"Walk"}]},{"name":"Nuclearo Dinossauro","anims":[{"id":"96833041107123","type":"Idle"},{"id":"111749482702667","type":"Walk"}]},{"name":"Odin Din Din Dun","anims":[{"id":"129613052461946","type":"Idle"},{"id":"109148658141773","type":"Walk"}]},{"name":"Orangutini Ananassini","anims":[{"id":"75222305207420","type":"Idle"},{"id":"105036102922047","type":"Walk"}]},{"name":"Orcalero Orcala","anims":[{"id":"119272575001982","type":"Idle"},{"id":"112020855822385","type":"Walk"}]},{"name":"Pandaccini Bananini","anims":[{"id":"103106055043597","type":"Idle"},{"id":"128684663901723","type":"Walk"}]},{"name":"Perochello Lemonchello","anims":[{"id":"90498571873126","type":"Idle"},{"id":"92206983262526","type":"Walk"}]},{"name":"Piccione Macchina","anims":[{"id":"115680775206155","type":"Idle"},{"id":"90224034806173","type":"Walk"}]},{"name":"Pipi Kiwi","anims":[{"id":"87967571457749","type":"Idle"},{"id":"120527188536758","type":"Walk"}]},{"name":"Pot Hotspot","anims":[{"id":"102710368207453","type":"Idle"},{"id":"92354416311625","type":"Walk"}]},{"name":"Rhino Toasterino","anims":[{"id":"78472092818251","type":"Idle"},{"id":"84638020964051","type":"Walk"}]},{"name":"Salamino Penguino","anims":[{"id":"77906763421812","type":"Idle"},{"id":"137954211713514","type":"Walk"}]},{"name":"Secret Lucky Block","anims":[{"id":"97941213049282","type":"Idle"},{"id":"97941213049282","type":"Walk"}]},{"name":"Spioniro Golubiro","anims":[{"id":"113785025997652","type":"Idle"},{"id":"94264416907805","type":"Walk"}]},{"name":"Statutino Libertino","anims":[{"id":"133831164655816","type":"Idle"},{"id":"132494284807830","type":"Walk"}]},{"name":"Strawberrelli Flamingelli","anims":[{"id":"88255836329470","type":"Idle"},{"id":"131535166116255","type":"Walk"}]},{"name":"Svinina Bombardino","anims":[{"id":"81782838365207","type":"Idle"},{"id":"140241938258969","type":"Walk"}]},{"name":"Ta Ta Ta Ta Sahur","anims":[{"id":"121116117231986","type":"Idle"},{"id":"135588924192019","type":"Walk"}]},{"name":"Talpa Di Fero","anims":[{"id":"91486133655850","type":"Idle"},{"id":"92201671180155","type":"Walk"}]},{"name":"Tigrilini Watermelini","anims":[{"id":"78391607722757","type":"Idle"},{"id":"73744398364127","type":"Walk"}]},{"name":"Tigroligre Frutonni","anims":[{"id":"88236966212570","type":"Idle"},{"id":"80336901554649","type":"Walk"}]},{"name":"Tim Cheese","anims":[{"id":"92703071789622","type":"Idle"},{"id":"73487969672476","type":"Walk"}]},{"name":"Torrtuginni Dragonfrutini","anims":[{"id":"109936028665028","type":"Idle"},{"id":"131883175739271","type":"Walk"}]},{"name":"Tralalero Tralala","anims":[{"id":"108564960767534","type":"Idle"},{"id":"98944511529574","type":"Walk"}]},{"name":"Trenostruzzo Turbo 3000","anims":[{"id":"124495673616983","type":"Idle"},{"id":"130167310194254","type":"Walk"}]},{"name":"Tric Trac Baraboom","anims":[{"id":"106065762831895","type":"Idle"},{"id":"108619270669135","type":"Walk"}]},{"name":"Trippi Troppi","anims":[{"id":"95904301602934","type":"Idle"},{"id":"93703316257474","type":"Walk"}]},{"name":"Trulimero Trulicina","anims":[{"id":"74273960343871","type":"Idle"},{"id":"86230487080083","type":"Walk"}]},{"name":"Tung Tung Tung Sahur","anims":[{"id":"137976164793614","type":"Idle"},{"id":"77274779078096","type":"Walk"}]},{"name":"Zibra Zubra Zibralini","anims":[{"id":"89001492026593","type":"Idle"},{"id":"77573901869885","type":"Walk"}]}]
"""
# ==============================================================================

def clean_and_parse_json(raw_text):
    try:
        start = raw_text.find('[')
        end = raw_text.rfind(']') + 1
        if start == -1 or end == 0: return None
        return json.loads(raw_text[start:end])
    except:
        return None

def download_asset(session, headers, asset_id, filename, filepath, counter):
    try:
        # STEP A: Ask the website to fetch the file
        payload = {'assetId': asset_id}
        response = session.post(WEBSITE_URL, data=payload, headers=headers, timeout=15)
        
        if response.status_code == 200:
            try:
                result_json = response.json()
            except:
                return f"❌ [{counter}] {filename}: Invalid JSON."

            if result_json.get('error'):
                 return f"❌ [{counter}] {filename}: {result_json.get('message', 'Unknown error')}"
            
            server_filename = result_json.get('file')
            if server_filename:
                # STEP B: Download the actual file
                download_link = f"{WEBSITE_URL}?download=1&file={server_filename}"
                file_response = session.get(download_link, headers=headers, timeout=15)
                
                if file_response.status_code == 200:
                    with open(filepath, 'wb') as f:
                        f.write(file_response.content)
                    return f"✅ [{counter}] Downloaded: {filename}"
        return f"❌ [{counter}] {filename}: Failed (Status: {response.status_code})"
    except Exception as e:
        return f"❌ [{counter}] {filename}: {e}"

def download_via_middleman():
    data = clean_and_parse_json(RAW_DATA)
    if not data:
        print("❌ ERROR: Invalid JSON data.")
        return

    if not os.path.exists("downloaded_anims"):
        os.makedirs("downloaded_anims")

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
    }

    print(f"🔥 Starting Optimized Download via {WEBSITE_URL}...")
    
    start_time = time.time()
    counter = 1
    
    with requests.Session() as session:
        for character in data:
            char_name = character['name']
            for anim in character['anims']:
                anim_type = anim['type']
                asset_id = anim['id']
                filename = f"{counter:03d}_{char_name}_{anim_type}.rbxm".replace(" ", "_")
                filepath = os.path.join("downloaded_anims", filename)
                
                result = download_asset(session, headers, asset_id, filename, filepath, counter)
                print(result)
                counter += 1

    end_time = time.time()
    print(f"\n✨ Done! Processed {counter-1} animations in {end_time - start_time:.2f} seconds.")

if __name__ == "__main__":
    download_via_middleman()

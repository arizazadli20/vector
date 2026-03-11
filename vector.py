import os
import speech_recognition as sr
import google.generativeai as genai
import subprocess

# --- AYARLAR ---
# Bura öz API açarını dırnaq içində yaz:
API_KEY = "AIzaSyBMnGVdsxAopVYTxwYEnwWgkC2vgOR0B3s" 
genai.configure(api_key=API_KEY)
model = genai.GenerativeModel('gemini-1.5-flash')

def danis(metn):
    print(f"İdrak: {metn}")
    # macOS-un daxili səsi (çox sürətlidir)
    os.system(f'say -v Damayanti "{metn}"') 

def proqram_ac(ad):
    danis(f"Bəli cənab, {ad} açılır.")
    # macOS-da proqramı açmaq üçün sistem komandası
    subprocess.run(["open", "-a", ad])

def qulaq_as():
    r = sr.Recognizer()
    with sr.Microphone() as source:
        print("Sizi dinləyirəm...")
        audio = r.listen(source)

    try:
        sual = r.recognize_google(audio, language="az-AZ")
        print(f"Siz: {sual}")
        return sual.lower()
    except:
        return ""

# --- ANA DÖVRÜYYƏ ---
if __name__ == "__main__":
    danis("Sistem aktivdir. Mən hazıram.")
    
    while True:
        komanda = qulaq_as()
        
        if "aç" in komanda:
            # Məsələn: "Safari aç" desən, "Safari" hissəsini götürür
            app_name = komanda.replace("aç", "").strip().capitalize()
            proqram_ac(app_name)
        
        elif "dayan" in komanda or "sağ ol" in komanda:
            danis("Görüşənədək!")
            break
            
        elif komanda != "":
            # Digər hər şey üçün Gemini cavab verir
            response = model.generate_content(f"Sən mənim köməkçimsən. Qısa cavab ver: {komanda}")
            danis(response.text)
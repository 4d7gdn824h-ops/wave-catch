# Wave Catch – Game Design Document (wersja 0.1)

**Platforma:** iOS (iPhone, App Store) · **Orientacja:** pionowa, gra jedną ręką · **Gatunek:** zręcznościowa gra refleksowa (arcade)  
**Odbiorcy dokumentu:** Marcin (właściciel), asystent Game Design, asystent Game Engineer  
**Status:** szkic do prototypu · **Data:** 9 października 2026

---

## 1. Pitch w jednym zdaniu + USP

**Pitch:** Jesteś surferem o zachodzie słońca – przeskakuj między 4 pozycjami na desce i łap wszystko, co wyrzucają fale, zanim tempo stanie się szalone.

**USP (co nas wyróżnia):**

- **Prosta, „kieszonkowa” mechanika 4 pozycji** – zrozumiała w 3 sekundy, gra jedną ręką w pionie, idealna na krótkie sesje (1–3 min).
- **Big Wave** – cykliczna fala bonusowa z mnożnikiem punktów, która daje rytm „napięcie → nagroda”.
- **Własna, rozpoznawalna oprawa** – jaskrawy retro-styl plaży lat 80. (neon, zachody słońca, synthwave), zamiast nostalgicznej kopii starych konsolek LCD.
- **Uczciwy model free-to-play** – bez paywalli i agresywnych reklam; płaci się za brak reklam i kosmetykę.

---

## 2. Rdzeń rozgrywki i sterowanie

**Pętla rozgrywki (core loop):**

1. Surfer stoi na desce na środku ekranu i może zająć jedną z **4 stałych pozycji**: lewa-góra, prawa-góra, lewa-dół, prawa-dół (wychylenie/sięgnięcie w danym kierunku).
2. Z 4 kierunków (4 „rynny” fal, po jednej na róg) toczą się / lecą obiekty w stronę surfera.
3. Obiekt dociera do końca rynny – jeśli surfer jest w odpowiedniej pozycji, **łapie go** (punkty). Jeśli nie – **pudło** (utrata życia).
4. Tempo i liczba obiektów rosną. **3 pudła = koniec gry.** Wynik → tabela wyników → „Jeszcze raz” jednym tapnięciem.

**Zasada czytelności:** każdy obiekt porusza się w dyskretnych „krokach” (np. 4–5 pozycji na rynnie) lub płynnie, ale z wyraźnym punktem „za chwilę spadnie” (błysk/dźwięk). Gracz musi zawsze widzieć, który róg wymaga reakcji. (Krokowy vs. płynny ruch – do przetestowania w prototypie.)

**Sterowanie:**

- **Domyślnie: tap w strefy dotyku.** Dolna połowa ekranu podzielona na siatkę 2×2 – każda ćwiartka odpowiada jednej pozycji surfera. Dzięki temu cała obsługa mieści się w zasięgu kciuka (gra jedną ręką), a górna część ekranu to czyste pole gry.
- **Alternatywa (opcja w ustawieniach): swipe** – przesunięcie po skosie (↖ ↗ ↙ ↘) przestawia surfera w dany róg.
- Zmiana pozycji jest **natychmiastowa** (bez animacji blokującej sterowanie) – animacja jest tylko kosmetyczna.
- Wsparcie: haptyka (krótka wibracja przy złapaniu, mocniejsza przy pudle), tryb dla leworęcznych nie jest potrzebny (siatka symetryczna), opcja większych stref dotyku w ustawieniach dostępności.

---

## 3. Obiekty

### Do łapania
| Obiekt | Punkty | Uwagi |
|---|---|---|
| **Muszla** | 1 | Podstawowy, najczęstszy obiekt. |
| **Mała deska surfingowa** | 2 | Nieco szybsza niż muszla. |
| **Koło ratunkowe** | 3 | Rzadsze; po złapaniu 5 kół z rzędu bez pudła – odzyskanie 1 życia (maks. 3). |

### Do unikania
| Obiekt | Efekt |
|---|---|
| **Skacząca meduza** | Porusza się po rynnie „podskokami” (nieregularny rytm). Jeśli surfer stoi w jej rogu, gdy dotrze do końca – **poparzenie = utrata życia** i reset combo. Jeśli surfera tam nie ma – meduza bezpiecznie wpada do wody (+0 pkt, ale nie przerywa combo). |

Meduza wymusza decyzję: czasem trzeba **świadomie odpuścić róg**, co jest głównym źródłem napięcia poza samą szybkością.

### Power-upy (3, pojawiają się rzadko jako obiekty do złapania)

1. **Okulary przeciwsłoneczne – „Slow Sun”**: przez 5 s wszystko zwalnia o ok. 30%.
2. **Tarcza z pianki – „Foam Shield”**: chroni przed jednym pudłem lub jednym poparzeniem meduzą.
3. **Magnes-muszla – „Tide Magnet”** (opcjonalnie, po MVP): przez 4 s obiekty z sąsiedniego rogu też zostają złapane.

Wszystkie wartości liczbowe w dokumencie to **punkt startowy do strojenia** w prototypie, nie ostateczne parametry.

---

## 4. Progresja trudności i tryby

**Progresja (we wszystkich trybach):**

- Prędkość obiektów rośnie stopniowo co określoną liczbę złapanych obiektów (np. co 10).
- Rośnie liczba obiektów jednocześnie na ekranie (od 1 do maks. 4–5).
- Meduzy pojawiają się dopiero po pierwszych kilkudziesięciu punktach, potem coraz częściej.
- Krótkie „oddechy” (chwilowe zwolnienie) po każdej Big Wave – żeby krzywa trudności była falą, a nie prostą linią.
- Generowanie obiektów: losowe, ale z regułami uczciwości (np. nigdy 2 obiekty kończące rynnę w tej samej chwili w przeciwnych rogach przy dużej prędkości).

**Tryby:**

1. **Klasyczny** – 3 życia, rosnące tempo, Big Wave co ok. 30–45 s. Główny tryb i główny ranking.
2. **Big Wave (endless)** – wolniejszy start, ale Big Wave pojawia się częściej i mnożnik kumuluje się między falami; wariant dla graczy szukających „flow” i wysokich wyników. Osobny ranking.
3. **Daily Challenge (wyzwanie dnia)** – ten sam układ (stały seed losowania) dla wszystkich graczy danego dnia, plus modyfikator dnia (np. „tylko meduzy w górnych rogach”, „podwójna prędkość, 5 żyć”). Jedna punktowana próba dziennie (dodatkowe próby treningowe bez rankingu). Dzienny ranking.

---

## 5. Punktacja, życia, combo

- **Punkty bazowe:** muszla 1, deska 2, koło 3 (patrz sekcja 3).
- **Combo:** każde kolejne złapanie bez pudła zwiększa licznik combo. Progi: 10 → ×1,5, 25 → ×2, 50 → ×3. Pudło lub poparzenie zeruje combo.
- **Big Wave:** co pewien czas zapowiedź (dźwięk + kolor nieba), potem przez **ok. 5–8 s** wielka fala: szybki strumień obiektów, mnożnik **×3** (sumuje się z combo – do zbalansowania), meduz brak lub bardzo mało. Pudła w trakcie Big Wave **nie odbierają życia**, tylko zerują mnożnik fali – to moment nagrody, nie kary.
- **Życia:** 3 (ikony desek w rogu ekranu). Utrata przy pudle lub poparzeniu. Odzysk: 5 kół ratunkowych z rzędu (maks. 3 życia).
- **Kontynuacja:** raz na grę możliwość „drugiej szansy” (+1 życie) za obejrzenie reklamy z nagrodą – zawsze opcjonalnie, bez presji czasu na decyzję dłuższej niż kilka sekund.
- **Ekran końca gry:** wynik, rekord osobisty, najdłuższe combo, przycisk „Jeszcze raz” (największy), ranking.

---

## 6. Oprawa wizualna i audio (oryginalna, retro lat 80.)

**Wizualnie:**

- Kolorowy, **pełnokolorowy** styl retro-plażowy lat 80.: zachód słońca w paski, gradienty róż–pomarańcz–fiolet, palmy, neonowe kontury, lekki efekt „VHS/scanline” jako opcja.
- **Nie naśladujemy wyglądu ekranu LCD** (żadnych szarych segmentowych sylwetek, ramki konsolki, segmentowych cyferek w stylu Elektroniki/Game & Watch).
- Surfer: własna postać (człowiek, nie zwierzę z kreskówek), kilka skórek kosmetycznych.
- Pora dnia zmienia się w trakcie gry (popołudnie → zachód → noc z neonami) jako wizualny wskaźnik postępu.
- Czytelność ponad efekty: obiekty z mocnym konturem, meduza wyraźnie odróżniona kolorem (np. fioletowo-trująca) od obiektów do łapania. Sprawdzić czytelność dla daltonistów (kształt, nie tylko kolor).

**Audio:**

- **Całkowicie oryginalna muzyka** w klimacie synthwave/surf-rock (zamówiona lub z licencją z jasnym prawem do użytku komercyjnego w grze). Żadnych motywów z kreskówek ani coverów znanych melodii.
- Muzyka przyspiesza / zmienia warstwę w czasie Big Wave.
- Krótkie, różne dźwięki dla każdego typu obiektu, pudła, poparzenia i combo (dźwięki pomagają grać „na słuch”).
- Osobne suwaki: muzyka / efekty; gra respektuje przełącznik wyciszenia iPhone'a.

---

## 7. Monetyzacja

Zasada: **gra ma być w pełni grywalna za darmo, bez paywalli i bez reklam przerywających rozgrywkę w trakcie.**

- **Free-to-play** – darmowe pobranie, wszystkie tryby dostępne.
- **Reklamy z nagrodą (rewarded ads), zawsze dobrowolne:** druga szansa w grze, podwojenie dziennej nagrody kosmetycznej (waluty miękkiej), dodatkowa próba treningowa w daily challenge.
- **Reklamy pełnoekranowe (interstitial) – opcjonalnie i oszczędnie:** najwyżej po zakończeniu gry, z limitem częstotliwości (np. nie częściej niż co kilka gier i nie w pierwszych minutach). Decyzja do podjęcia; można zacząć wyłącznie od rewarded ads.
- **Jednorazowy zakup „Usuń reklamy”** (non-consumable IAP) – usuwa reklamy pełnoekranowe; rewarded ads pozostają jako opcja lub nagrody przyznawane są bez reklamy (do decyzji). Obowiązkowy przycisk „Przywróć zakupy”.
- **Kosmetyka:** deski, stroje surfera, motywy nieba/plaży. Do zdobycia za grę (osiągnięcia, waluta miękka) i/lub do kupienia w małych pakietach. **Kosmetyka nie daje przewagi w grze.**
- Bez loot boxów, bez energii/limitu gier, bez sztucznych liczników „oferta kończy się za 5 min”.

---

## 8. Retencja

- **Daily Challenge** z dziennym rankingiem i seria dni z rzędu (streak) nagradzana kosmetyką.
- **Game Center:** rankingi (Klasyczny, Big Wave, Daily), osiągnięcia (np. „Pierwsza Big Wave”, „Combo 50”, „Unikaj 100 meduz”, „7 dni z rzędu”).
- **Cele krótkoterminowe:** 3 proste misje dzienne (np. „złap 30 kół ratunkowych”).
- **Odblokowania kosmetyczne** za rekordy i osiągnięcia – widoczny postęp nawet przy słabszej sesji.
- **Powiadomienia:** tylko za zgodą gracza i oszczędnie (np. 1 dziennie: „nowe wyzwanie dnia”). Domyślnie nie wymuszamy zgody na starcie.

---

## 9. Bezpieczeństwo IP – checklista

Inspirujemy się wyłącznie **ogólną mechaniką** (łapanie obiektów na 4 torach, 4 pozycje gracza, rosnące tempo, 3 pudła). Ogólne zasady gry zazwyczaj nie podlegają ochronie, ale **konkretna oprawa, postacie, nazwy, dźwięki i wygląd urządzenia – tak.**

**Unikamy (checklista):**

- [ ] Brak wilka, zająca ani jakichkolwiek postaci z kreskówki „Nu, pogodi!” lub do nich podobnych.
- [ ] Brak jajek i kurczaków/kur jako obiektów i grafik.
- [ ] Brak nazwy „Nu, pogodi!” (i jej wariantów, transliteracji, aluzji) w nazwie, opisie, słowach kluczowych App Store, grafikach i materiałach marketingowych.
- [ ] Brak nazw „Elektronika”, „IM-02”, „Game & Watch”, „Egg”, „Nintendo” w nazwie, słowach kluczowych i materiałach promocyjnych.
- [ ] Brak wyglądu ekranu LCD z segmentowymi sylwetkami, ramki konsolki, charakterystycznego układu przycisków i kolorystyki tych urządzeń (trade dress).
- [ ] Brak muzyki, melodii, dźwięków i sampli z kreskówki ani z oryginalnych gier; cała muzyka i SFX oryginalne lub z jasną licencją komercyjną (zachować dokumenty licencyjne).
- [ ] Układ 4 torów i postaci zaprojektowany od nowa (kierunki fal, plaża, surfer), a nie przerysowany z oryginału.
- [ ] Wszystkie grafiki, fonty i assety z udokumentowanym źródłem i licencją; umowy z twórcami z przeniesieniem praw autorskich.
- [ ] W marketingu nie używamy haseł typu „jak stara gra z wilkiem” ani zrzutów oryginałów.

**Ważne:** Ten dokument nie jest poradą prawną. **Przed publikacją należy potwierdzić całość z prawnikiem specjalizującym się w prawie własności intelektualnej** (prawa autorskie, znaki towarowe, trade dress) – w szczególności nazwę gry, logo i ogólne podobieństwo oprawy. Warto też sprawdzić bazy znaków towarowych (np. EUIPO, USPTO, UPRP) dla wybranej nazwy.

---

## 10. Zakres MVP na prototyp

**Cel prototypu:** odpowiedzieć na jedno pytanie – *czy łapanie na 4 pozycjach z meduzami i Big Wave jest fajne i „jeszcze jedna gra” działa?*

**W MVP (najmniejsza grywalna wersja):**

- 1 ekran gry w pionie, surfer w 4 pozycjach, sterowanie tap 2×2 (swipe jako przełącznik w debugu).
- 4 rynny, 2 obiekty do łapania (muszla, deska) + meduza.
- Rosnąca prędkość, 3 życia, game over, restart jednym tapnięciem.
- Punkty + combo + jedna Big Wave z mnożnikiem.
- Proste placeholderowe grafiki (kolorowe kształty) i podstawowe dźwięki/haptyka.
- Lokalny rekord (zapis na urządzeniu).
- **Panel debugowania** z suwakami: prędkość, częstotliwość obiektów, szansa na meduzę, czas Big Wave – żeby Game Design mógł stroić grę bez programowania.

**Poza MVP:** power-upy, tryby Big Wave i Daily, Game Center, reklamy, IAP, kosmetyka, finalna grafika i muzyka.

**Sugerowana technologia:**

- **Rekomendacja: Swift + SpriteKit (z SwiftUI do menu).** Natywne dla iOS, darmowe, wbudowane w Xcode, łatwa integracja z Game Center, StoreKit i haptyką; gra 2D o tej skali nie potrzebuje więcej.
- **Alternatywa wieloplatformowa (jeśli w przyszłości Android): Godot** (darmowy, otwarty) lub **Unity** (większy ekosystem reklam/analityki, ale cięższy i z licencją do sprawdzenia). Wybór warto podjąć przed startem prototypu, bo zmiana później oznacza przepisanie gry.

**Kamienie milowe (bez estymacji czasu):**

1. **M0 – Decyzje:** wybór technologii, konto Apple Developer, repozytorium, ustalenie nazwy roboczej.
2. **M1 – Szary prototyp:** ruch surfera, 4 rynny, łapanie/pudło, game over. Test na własnym iPhonie.
3. **M2 – Fajność:** combo, meduza, Big Wave, krzywa trudności, panel debugowania, haptyka. Testy z kilkoma osobami (TestFlight).
4. **M3 – Decyzja „go / no-go”:** czy gra jest wciągająca? Ewentualne zmiany mechaniki.
5. **M4 – Pełna gra:** power-upy, trzy tryby, Game Center, finalna oprawa i oryginalna muzyka.
6. **M5 – Monetyzacja i zgodność:** rewarded ads, IAP „Usuń reklamy”, kosmetyka, ustawienia prywatności, przegląd IP z prawnikiem.
7. **M6 – Wydanie:** strona w App Store, zrzuty ekranu, beta na TestFlight, wysyłka do recenzji Apple, premiera.

---

## 11. Uwagi do App Store

**Nazwa – propozycje (oprócz „Wave Catch”):**

- **Sunset Surf Catch**
- **Tide Catcher**
- **Surf & Snatch**
- **Neon Wave Rider**
- **Beach Reflex '85**

⚠️ **Dostępność wszystkich nazw (w tym „Wave Catch”) trzeba sprawdzić:** w App Store (nazwa aplikacji musi być unikalna w sklepie), w bazach znaków towarowych oraz pod kątem wolnej domeny/kont społecznościowych. Nazwa nie może nawiązywać do „Nu, pogodi!” ani urządzeń Elektronika/Game & Watch.

**Kategoria wiekowa:** gra bez przemocy, treści dla dorosłych ani hazardu – spodziewana **najniższa kategoria wiekowa (4+)**, ostatecznie zależna od odpowiedzi w kwestionariuszu Apple w App Store Connect. Uwaga: reklamy wyświetlane w grze muszą pasować do tej kategorii (filtrowanie treści reklam w ustawieniach sieci reklamowej).

**Prywatność:**

- Cel: **brak własnego zbierania danych** – brak kont, logowania, analityki śledzącej; rekordy i postęp zapisywane lokalnie (ewentualnie iCloud), rankingi przez Game Center (konto Apple gracza).
- **Uwaga:** zewnętrzne SDK reklamowe zwykle zbierają dane (np. identyfikatory urządzenia, dane o użyciu). Wtedy trzeba je uczciwie zadeklarować w etykiecie prywatności App Store („Privacy Nutrition Label”), a do reklam spersonalizowanych/śledzenia potrzebna jest zgoda ATT (App Tracking Transparency). Prostsza opcja: **tylko reklamy niespersonalizowane, bez proszenia o ATT** – do potwierdzenia, jakie dane zbiera wybrane SDK.
- Wymagana jest **polityka prywatności** (link w App Store i w grze) – również wtedy, gdy nie zbieramy danych.
- Jeśli gra miałaby być kierowana do dzieci (kategoria „Dla dzieci”), obowiązują dodatkowe, surowe zasady dot. reklam i danych – rekomendacja: **nie zgłaszać gry do kategorii Kids**, celować w ogólną publiczność.

---

*Koniec dokumentu. Wszystkie liczby (punkty, czasy, progi) są wartościami startowymi do strojenia w prototypie.*

# Translation glossary

The app speaks French, English, German, Spanish, Italian and Dutch
(`app/lib/i18n/<code>.i18n.json`, rules in `.claude/rules/translations.md`).
French carries the meaning; English is the base locale of the code and the
second reference. This file fixes the register, the formats and the trade
terms of each language, so a new key reads like the rest of its file. Change
a term here and in every key that uses it, in the same commit.

The readers are motorhome and van travellers, many of them 55 to 75, reading
at arm's length in a cab or hearing the guidance while driving. The bar is an
app written in their language, never a translation that shows.

## Register

| language | register | why |
|---|---|---|
| fr | vous | the source |
| en | you, neutral | the base |
| de | **Sie**, capitalised (`Sie`, `Ihr`, `Ihnen`) | Google Maps, Apple Karten, TomTom, ADAC and the motorhome press address the reader with Sie; du would read as too familiar to most of the audience |
| es | **tú** (Spain) | Google Maps, Apple Mapas, Waze and the travel apps of Spain use tú |
| it | **tu** | Google Maps, Apple Mappe, Waze and the routing engine's own Italian instructions (`Svolta a destra`, `Sei arrivato`) use tu |
| nl | **je / jij** (`je`, `jouw` when stressed) | Google Maps, ANWB, NS and the routing engine's own Dutch instructions (`Je bent op je bestemming aangekomen`) use je; `u` reads as an administration |

Buttons and menu items take the form each platform uses, not a sentence:
the infinitive in German, Spanish and Dutch (`Speichern`, `Guardar`,
`Opslaan`), the imperative in Italian (`Salva`, `Condividi`). A message that
addresses the reader uses the register above (`Tippen Sie auf die Karte`,
`Toca el mapa`, `Tocca la mappa`, `Tik op de kaart`).

Variants: German of Germany (with `ß`), Spanish of Spain (`aparcamiento`,
`móvil`, `coche`, `ordenador`), standard Italian, Dutch of the Netherlands
(understood in Flanders; avoid words only one side uses).

## Writing rules for every language

- **No em dash, no en dash** (the gates refuse them): a comma, a colon,
  parentheses or two sentences.
- Quotes: French `« »`, English `" "`, German `„ “`, Spanish and Italian
  `« »`, Dutch `“ ”`. The apostrophe is `'` (U+0027) in every file.
- Spanish opens its questions and exclamations (`¿…?`, `¡…!`). Italian writes
  its accents as accents (`è`, `più`, `perché`, `città`), never as an
  apostrophe. Dutch keeps its diaeresis (`kopiëren`, `Normandië`).
- Keep every parameter (`$name`, `$count`) and every slang key modifier
  (`daysAgo(param=n)`) exactly as in the source. Plural groups use `one` and
  `other`, plus `zero` where the source has one; slang applies the rule of
  each language (1 is `one`, 0 is `zero` when given, 1.5 is `other` outside
  French).
- German and Dutch run 20 to 35 % longer than French. On chips, tabs, rail
  labels, buttons, segmented controls and the guidance banner, take the
  shortest natural form (`Route`, `Filter`, `Teilen`); the full form goes in
  hints and screen reader labels, which may be complete sentences.
- Proper names stay as they are: Lunaway, OpenStreetMap, Protomaps, IGN,
  BD TOPO, Géoplateforme, DATAtourisme, Atout France, Etalab, Licence
  Ouverte 2.0, Base Adresse Nationale, Bison Futé, DiaLog, FINESS, La Poste,
  Panoramax, Wikimedia Commons, Mangrove Reviews, Photon, Natural Earth, NDW,
  DGT, the licences (ODbL, CC BY 4.0, MIT). Describe a French institution in
  the reader's language once (`das französische Wirtschaftsministerium`).
- The external community source is never named. Its contractual label,
  `Source communautaire externe`, is translated literally (table below).

## Formats

| | fr | en | de | es | it | nl |
|---|---|---|---|---|---|---|
| decimal | 2,90 | 2.90 | 2,90 | 2,90 | 2,90 | 2,90 |
| units | m, km, km/h, t, L/100 km | same | m, km, km/h, t, l/100 km | m, km, km/h, t, l/100 km | m, km, km/h, t, l/100 km | m, km, km/u, t, l/100 km |
| fuel price | 1,789 €/L | €1.789/L | 1,789 €/l | 1,789 €/l | 1,789 €/l | € 1,789/l |
| file size | ko, Mo | KB, MB | KB, MB | kB, MB | kB, MB | kB, MB |
| clock | 15:42 | 3:42 PM | 15:42 | 15:42 | 15:42 | 15:42 |
| duration (`$h`, `$m` padded to 2) | 1 h 05 | 1 h 05 | 1:05 Std. | 1 h 05 min | 1 h 05 min | 1 u 05 min |
| day and month (`$day $month`) | 6 oct. | Oct 6 | 6. Okt. | 6 oct. | 6 ott. | 6 okt. |
| weekdays | lun. mar. mer. jeu. ven. sam. dim. | Mon Tue … | Mo. Di. Mi. Do. Fr. Sa. So. | lun. mar. mié. jue. vie. sáb. dom. | lun mar mer gio ven sab dom | ma di wo do vr za zo |
| months | janv. févr. mars … | Jan Feb … | Jan. Feb. März Apr. Mai Juni Juli Aug. Sept. Okt. Nov. Dez. | ene. feb. mar. abr. may. jun. jul. ago. sept. oct. nov. dic. | gen feb mar apr mag giu lug ago set ott nov dic | jan. feb. mrt. apr. mei jun. jul. aug. sep. okt. nov. dec. |

Distances and speeds are metric in every language (km, km/h); miles and mph
appear only when the user picks them in the guidance settings.

## The spoken guidance

`navigation.voice.*` is read aloud by the device's own voice while the
reader drives, between the routing engine's instructions (Valhalla, in the
same language). Write it to be heard once, at speed:

- short sentences ending with a period; the most useful word first
  (`Achtung, …`, `Atención, …`, `Attenzione, …`, `Let op, …`);
- units as words, never symbols (`Meter`, `metros`, `metri`, `meter`;
  `Kilometer`, `kilómetros`, `chilometri`, `kilometer`; `Tonnen`,
  `toneladas`, `tonnellate`, `ton`); a size reads as it is said
  (`3 Meter 20`, `3 metros 20`, `3 metri e 20`, `3 meter 20`), in the
  singular for one metre or one tonne (plural groups: `un metro 90`);
- the distance comes first, as the engine says it (`In 300 Metern ist die
  Straße gesperrt`, `Over 300 meter een flitser`);
- the distance ahead takes the engine's own preposition: `in` (de), `en`
  (es), `tra` (it), `over` (nl);
- no parentheses, abbreviations or symbols the voice would spell out;
- the register of the engine: German is impersonal (`Ziel erreicht.`),
  Spanish speaks with usted (`Gire a la derecha`, `Ha llegado a su
  destino`), so the app's own Spanish sentences stay impersonal or use usted
  (`Ha llegado a su destino.`), Italian and Dutch use tu and je like the
  rest of their file.

The voice has three modes (`navigation.guidance.voiceMode`,
`navigation.settings.voice*`): the button's tooltip names the mode in full,
the profile's segmented choice takes the short form.

| | fr | en | de | es | it | nl |
|---|---|---|---|---|---|---|
| full voice | Voix complète (Complète) | Full voice (Full) | Alle Sprachansagen (Alle) | Voz completa (Completa) | Voce completa (Completa) | Volledige stem (Volledig) |
| alerts only | Voix : alertes seulement (Alertes) | Voice: alerts only (Alerts) | Sprachansagen: nur Warnungen (Warnungen) | Voz: solo alertas (Alertas) | Voce: solo avvisi (Avvisi) | Stem: alleen waarschuwingen (Waarschuwingen) |
| muted | Voix coupée (Coupée) | Voice off (Off) | Sprachansagen aus (Aus) | Voz silenciada (Silenciada) | Voce disattivata (Disattivata) | Stem uit (Uit) |
| the chime before an alert | court signal | short chime | kurzer Signalton | breve aviso sonoro | breve segnale acustico | kort signaal |

## Trade terms

| fr | en | de | es | it | nl |
|---|---|---|---|---|---|
| aire de camping-car | motorhome area | Wohnmobilstellplatz (short: Stellplatz) | área de autocaravanas | area sosta camper | camperplaats |
| aire de services | service area | Ver- und Entsorgungsstation (V/E-Station) | punto de servicio para autocaravanas | area camper service | camperservicepunt |
| borne de services | service point | V/E-Säule | punto de servicio | colonnina camper service | servicezuil |
| borne de vidange | dump station | Entsorgungsstation | punto de vaciado | punto di scarico | lozingspunt |
| vidange (eaux grises) | grey water disposal | Grauwasserentsorgung | vaciado de aguas grises | scarico acque grigie | grijswater lozen |
| vidange cassette | cassette (black water) disposal | Kassettenentleerung | vaciado de WC químico | scarico cassetta WC | cassette legen |
| eau potable | drinking water | Trinkwasser | agua potable | acqua potabile | drinkwater |
| électricité | electricity | Strom | electricidad | corrente elettrica | stroom |
| camping | campsite | Campingplatz | camping | campeggio | camping |
| parking | car park | Parkplatz | aparcamiento | parcheggio | parkeerplaats |
| aire de repos | rest area | Rastplatz | área de descanso | area di sosta stradale | rustplaats |
| aire de pique-nique | picnic area | Picknickplatz | área de pícnic | area picnic | picknickplaats |
| accueil à la ferme | farm stay | Stellplatz auf dem Bauernhof | granja | sosta in fattoria | camperplaats bij de boer |
| accueil chez un particulier | private host | bei Privatleuten | casa particular | ospitalità da privati | camperplaats bij een particulier |
| lieu en pleine nature | spot in the wild | Platz in freier Natur | lugar en plena naturaleza | sosta in natura | plek in de natuur |
| lieu (a spot on the map) | place | Platz (plural Plätze) | lugar | luogo | plek |
| nuit autorisée | overnight allowed | Übernachten erlaubt | pernocta permitida | pernottamento consentito | overnachten toegestaan |
| nuit tolérée | overnight tolerated | Übernachten geduldet | pernocta tolerada | pernottamento tollerato | overnachten gedoogd |
| de jour seulement | daytime only | nur tagsüber | solo de día | solo di giorno | alleen overdag |
| nuit interdite | no overnight stay | Übernachten verboten | pernocta prohibida | pernottamento vietato | overnachten verboden |
| sauf desserte, accès riverains | except for access | Anlieger frei | salvo para acceder a la zona | eccetto frontisti | uitgezonderd bestemmingsverkeer |
| gabarit (du véhicule) | vehicle size | Fahrzeugmaße | dimensiones del vehículo | dimensioni del veicolo | afmetingen van het voertuig |
| PTAC, poids total autorisé | gross vehicle weight (GVW) | zulässiges Gesamtgewicht (zGG) | masa máxima autorizada (MMA) | massa complessiva a pieno carico | toegestane maximummassa |
| carte grise | registration document | Fahrzeugschein | ficha técnica (for the dimensions) | libretto di circolazione | kentekenbewijs |
| camping-car | motorhome | Wohnmobil | autocaravana | camper | camper |
| van | van | Van | van | van | busje |
| fourgon aménagé | campervan | Kastenwagen | furgoneta camper | furgone camperizzato | buscamper |
| profilé | low-profile | Teilintegriert | perfilada | semintegrale | halfintegraal |
| capucine | over-cab | Alkoven | capuchina | mansardato | alkoof |
| intégral | A-class | Vollintegriert | integral | motorhome integrale | integraal |
| caravane | caravan | Wohnwagen | caravana | caravan | caravan |
| remorque | trailer | Anhänger | remolque | rimorchio | aanhanger |
| emplacements | pitches | Anzahl Stellplätze | plazas | posti | plaatsen |
| passage bas | low clearance | niedrige Durchfahrt | paso de altura limitada | passaggio basso | lage doorrijhoogte |
| pont bas | low bridge | niedrige Brücke | puente bajo | sottopasso | lage brug |
| barre de hauteur | height barrier | Höhenbegrenzung | barra de gálibo | barra limitatrice | hoogtebegrenzer |
| porche | building passage | Tordurchfahrt | paso bajo edificio | passaggio coperto | doorgang onder gebouw |
| passage étroit | narrow passage | Engstelle | paso estrecho | strettoia | versmalling |
| route non revêtue | unpaved road | unbefestigte Straße | camino sin asfaltar | strada sterrata | onverharde weg |
| péage | toll | Maut | peaje | pedaggio | tol |
| autoroute | motorway | Autobahn | autopista | autostrada | snelweg |
| radar | speed camera | Blitzer | radar | autovelox | flitser |
| zone de danger | danger zone | Gefahrenzone | zona de peligro | zona di pericolo | gevarenzone |
| radar fixe | fixed speed camera | fester Blitzer | radar fijo | autovelox fisso | vaste flitser |
| radar feu rouge | red light camera | Rotlichtblitzer | radar de semáforo | telecamera al semaforo | roodlichtcamera |
| radar de passage à niveau | level crossing camera | Blitzer am Bahnübergang | radar de paso a nivel | telecamera al passaggio a livello | flitser bij overweg |
| radar tronçon | average speed camera | Abschnittskontrolle | radar de tramo | Tutor | trajectcontrole |
| contrôle de vitesse moyenne | average speed check | Abschnittskontrolle (spoken alone, also its end) | control de velocidad media | controllo della velocità media | trajectcontrole |
| fin de la zone de danger | end of danger zone | Ende der Gefahrenzone | fin de la zona de peligro | fine della zona di pericolo | einde gevarenzone |
| position exacte des radars | exact speed camera positions | genaue Blitzerstandorte | ubicación exacta de los radares | posizione esatta degli autovelox | exacte locatie van flitsers |
| itinéraire | route | Route | ruta | percorso | route |
| Itinéraire (place action) | Directions | Route | Ruta | Percorso | Route |
| guidage | guidance | Navigation | navegación | navigazione | navigatie |
| étape | stop | Zwischenstopp (short: Stopp) | parada | tappa | tussenstop |
| départ, arrivée | start, destination | Start, Ziel | salida, destino | partenza, destinazione | vertrek, bestemming |
| carburant, gazole | fuel, diesel | Kraftstoff, Diesel | combustible, gasóleo | carburante, gasolio | brandstof, diesel |
| SP95, SP95-E10, SP98, E85 | Unleaded 95, E10, Unleaded 98, E85 | Super 95, Super E10, Super Plus 98, E85 | Gasolina 95, Gasolina 95 E10, Gasolina 98, E85 | Benzina 95, Benzina E10, Benzina 98, E85 | Euro 95 (E5), Euro 95 (E10), Super Plus 98, E85 |
| GPL | LPG | Autogas (LPG) | GLP | GPL | LPG |
| bouteilles de gaz | gas bottles | Gasflaschen | bombonas de gas | bombole del gas | gasflessen |
| station-service | fuel station | Tankstelle | gasolinera | distributore | tankstation |
| note (étoiles) | rating | Bewertung | valoración | valutazione | beoordeling |
| avis | review | Rezension | reseña | recensione | review |
| signalement | report | Meldung | aviso (road, place), denuncia (to moderation) | segnalazione | melding |
| Toujours là ? | Still there? | Noch da? | ¿Sigue ahí? | C'è ancora? | Is het er nog? |
| voyageur | traveller | Reisende, Reisender | viajero | viaggiatore | reiziger |
| contribution | contribution | Beitrag | contribución | contributo | bijdrage |
| modération | moderation | Moderation | moderación | moderazione | moderatie |
| pseudonyme | pseudonym | Pseudonym | seudónimo | pseudonimo | pseudoniem |
| niveau de confiance | trust level | Vertrauensstufe | nivel de confianza | livello di fiducia | vertrouwensniveau |
| carte de secours | recovery card | Sicherungskarte | tarjeta de recuperación | scheda di recupero | herstelkaart |
| code de secours | recovery code | Sicherungscode | código de recuperación | codice di recupero | herstelcode |
| favoris, Mes favoris | favourites, My favourites | Favoriten, Meine Favoriten | favoritos, Mis favoritos | preferiti, I miei preferiti | favorieten, Mijn favorieten |
| hors ligne, cartes hors ligne | offline, offline maps | offline, Offline-Karten | sin conexión, mapas sin conexión | offline, mappe offline | offline, offline kaarten |
| votre position | your position | Ihr Standort | tu ubicación | la tua posizione | je positie |
| pas de réseau | no network | keine Verbindung | sin conexión | nessuna rete | geen verbinding (zonder internet) |
| commune | town | Gemeinde | municipio | comune | gemeente |
| fiche (d'un lieu) | place page | Platzseite | ficha | scheda | detailpagina |
| Source communautaire externe | External community source | Externe Community-Quelle | Fuente comunitaria externa | Fonte comunitaria esterna | Externe communitybron |
| Externe (short label) | External | Extern | Externa | Esterna | Extern |

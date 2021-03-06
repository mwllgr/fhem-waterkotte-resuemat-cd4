# $Id$
# fhem Modul für Waterkotte Wärmepumpe mit Resümat CD4 Steuerung
# Vorlage: Modul WHR962, diverse Foreneinträge sowie Artikel über Auswertung der
# Wärmepumpe mit Linux / Perl im Linux Magazin aus 2010
# insbesondere:
#       http://www.haustechnikdialog.de/Forum/t/6144/Waterkotte-5017-3-an-den-Computer-anschliessen?page=2  (Speicheradressen-Liste)
#       http://www.ip-symcon.de/forum/threads/2092-ComPort-und-Waterkotte-abfragen                          (Protokollbeschreibung)
#       http://www.haustechnikdialog.de/Forum/t/6144/Waterkotte-5017-3-an-den-Computer-anschliessen?page=4  (Beispiel Befehls-Strings)
#
# Ausgeführte Änderungen:
#       Speicheradressen für Readings an SW-Version 8011 angepasst
#       Abfrage-Bytes auf 0x11B verringert (ansonsten zu viel für SW-Version 8011: max. 152)
#       Mehrere Get- und Set-Abfragen hinzugefügt
#       Min-/Max-Werte bei allen sets hinzugefügt
#       "Status"-Reading entfernt (kann aber unten aktiviert werden, einfach Kommentar-# entfernen)
#       Wakeup-Command geändert, als Nebeneffekt wird die Aussentemperatur öfters abgefragt
#       WARNING bezüglich set hinzugefügt
#       Menüeinträge und Abfrage dieser per get implementiert
#       Kommentare geändert, Stil weitestgehend vereinheitlicht
#       Binäre Werte können nun auch gesetzt werden
#       Datum/Uhrzeit-Felder können gesetzt werden (Gilt nicht für "Datum", "Uhrzeit" und "Zeit"!)
#       Betriebs-Mode kann gesetzt werden
#       Fortgeschrittenen-Modus via Attribut "enableAdvancedMode" implementiert
#       Uhrzeit-/Datum kann jetzt mit FHEM-Server synchronisiert werden
#       "Lesbare" Readings für Binärfelder wie "Do-Buffer" etc.
#
# ---- !! WARNING !! ----
# This module could destroy your heating if something goes extremely wrong!
# Be careful, especially with set commands. Min/max values MIGHT NOT be correct for your control unit.
# ---- END OF WARNING ----

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Time::Piece;
use Encode qw(decode encode);

#
# List of readings / values that can be written to the heat pump
my %WKRCD4_sets_default = (
    "Hz-KlSteilheit" => "Hz-KlSteilheit",
    "Hz-Temp-BasisSoll" => "Hz-Temp-BasisSoll",
    "Hz-Temp-Einsatz" => "Hz-Temp-Einsatz",
    "Hz-Temp-RaumSoll" => "Hz-Temp-RaumSoll",
    "Hz-SchnellAufhz" => "Hz-SchnellAufhz",
    "Ww-Temp-Soll" => "Ww-Temp-Soll",
    "Hz-Abschaltung" => "Hz-Abschaltung",
    "Ww-Abschaltung" => "Ww-Abschaltung",
);

my %WKRCD4_sets = %WKRCD4_sets_default;

#
# List of readings / values that can explicitely be requested
# from the heat pump with the FHEM-Get command
my %WKRCD4_gets = %WKRCD4_sets;

# You can add more gets here:
my %WKRCD4_gets_more = (
  # "Uhrzeit" => "Uhrzeit",
);

# Merge the two get-hashes
%WKRCD4_gets = (%WKRCD4_gets, %WKRCD4_gets_more);

# Advanced set/get commands, have to be enabled first
# Enable with:      attr DEVICE enableAdvancedMode 1
my %WKRCD4_advanced = (
  "Hz-Zeit-Ein" => "Hz-Zeit-Ein",
  "Hz-Zeit-Aus" => "Hz-Zeit-Aus",
  "Hz-Anhebung-Ein" => "Hz-Anhebung-Ein",
  "Hz-Anhebung-Aus" => "Hz-Anhebung-Aus",
  "Hz-Temp-RaumSoll" => "Hz-Temp-RaumSoll",
  "Hz-Raum-Einfluss" => "Hz-Raum-Einfluss",
  "Hz-Ext-Anhebung" => "Hz-Ext-Anhebung",
  "Hz-Begrenzung" => "Hz-Begrenzung",
  "Hz-Stufe2-Begrenzung" => "Hz-Stufe2-Begrenzung",
  "Hz-Hysterese" => "Hz-Hysterese",
  "Hz-PumpenNachl" => "Hz-PumpenNachl",
  "Ww-Zeit-Ein" => "Ww-Zeit-Ein",
  "Ww-Zeit-Aus" => "Ww-Zeit-Aus",
  "Ww-Becken-Temp-Soll" => "Ww-Becken-Temp-Soll",
  "Ww-Hysterese" => "Ww-Hysterese",
  "Ww-Becken-Hysterese" => "Ww-Becken-Hysterese",
  # -- Disabled because not needed usually --
  # "Mess-Reset" => "Mess-Reset",
  # "Kompr-Mess-Reset" => "Kompr-Mess-Reset",
  # --
  "Ausfall-Reset" => "Ausfall-Reset",
  "Unterdr-Warnung-Eingang" => "Unterdr-Warnung-Eingang",
  "Unterdr-Warnung-Ausgang" => "Unterdr-Warnung-Ausgang",
  "Unterdr-Warnung-Sonstige" => "Unterdr-Warnung-Sonstige",
  "Do-Handkanal" => "Do-Handkanal",
  "Do-Handkanal-Ein" => "Do-Handkanal-Ein",
  "Kennwort" => "Kennwort",
  # -- Disabled because dangerous/not needed usually --
  # "Werkseinstellung" => "Werkseinstellung",
  # "Betriebs-Mode" => "Betriebs-Mode",
  # --
  "ResetAnforderung" => "ResetAnforderung",
  "Modem-Klingelzeichen" => "Modem-Klingelzeichen",
  "Fremdzugriff" => "Fremdzugriff",
  "Schluesselnummer" => "Schluesselnummer",
  "Hz-Ext-Freigabe" => "Hz-Ext-Freigabe",
  "Hz-Ext-TempRueckl-Soll" => "Hz-Ext-TempRueckl-Soll",
  "St2-Temp-QAus-Min" => "St2-Temp-QAus-Min",
  "St2-Temp-Verdampfer-Min" => "St2-Temp-Verdampfer-Min",
  "Estrich-Aufhz" => "Estrich-Aufhz",
  "Hz-Ext-Steuerung" => "Hz-Ext-Steuerung",
  "St2-bei-EvuAbsch" => "St2-bei-EvuAbsch",
  "Freigabe-Beckenwasser" => "Freigabe-Beckenwasser",
  "AnalogKorrFaktor" => "AnalogKorrFaktor",
  "Run-Flag" => "Run-Flag",
);

# Binary value-arrays as hash
my %WKRCD4_BinaryValues = (
  "Mode-Heizung" => ["UnterbrFuehlerfehler", "KeinBedarf", "Unterdrueckt", "Zeitprog", "Sommer", "SchnellAufhz", "ExtAnheb", "Normal"],
  "Mode-Wasser" => ["", "", "", "Unterdrueckt", "UnterbrFuehlerfehler", "KeinBedarf", "Zeitprog", "Normal"],
  "Betriebszustaende" => ["Ext. Steuerung", "", "", "Unterbrechung", "Hand-Betrieb", "St2-Betrieb", "Hz-Betrieb", "Ww-Betrieb"],

  "Do-Buffer" => ["Pumpe-Quelle", "Pumpe-Ww", "Pumpe-Hz", "St2", "Kurbelwannenhz", "Alarm", "Kompr-1", "Magnetventil"],
  "Di-Buffer" => ["Ext-Abschaltung", "Ext-Sollwertbeeinflussung", "", "Sole-Minimum",
                  "Pumpe-Quelle", "HD-Pressostat", "ND-Pressostat", "Oeldruck/Kompr-Störung"],

  "Warnung-Eingang" => ["", "", "", "",
                        "Diff. QAus-Verdampf zu hoch", "Diff. QEin-QAus zu hoch",
                        "Temp. QAus zu niedrig", "Verdampfungstemp. zu niedrig"],

  "Warnung-Ausgang" => ["", "", "Diff. Kondensation-Vorlauf zu hoch", "", "Diff. HzgVorlauf-Ruecklauf zu hoch",
                        "Diff. HzgVorlauf-Ruecklauf zu niedrig", "Kondensationstemp. zu hoch", ""],

  "Warnung-Sonstige" => ["", "", "", "Solestand Minimum", "Do-Buffer in Handstellung",
                        "Außenfuehler defekt", "Hz-Vorlauffuehler defekt", "Hz-Ruecklauffuehler defekt"],
			
  "Unterbrechungen" => ["Temp. Hz-Vorlauf zu hoch", "Ww-Fuehler defekt", "Hz-Fuehler defekt", "WPumpe-Fuehler defekt",
                        "Schalthaeufigkeit", "Ext. Abschaltung", "Temp. QAus zu niedrig", "Ungueltiger Betriebs-Mode"],
);

$WKRCD4_BinaryValues{"Unterdr-Warnung-Eingang"} = $WKRCD4_BinaryValues{"Warnung-Eingang"};
$WKRCD4_BinaryValues{"Unterdr-Warnung-Ausgang"} = $WKRCD4_BinaryValues{"Warnung-Ausgang"};
$WKRCD4_BinaryValues{"Unterdr-Warnung-Sonstige"} = $WKRCD4_BinaryValues{"Warnung-Sonstige"};
$WKRCD4_BinaryValues{"Ausfall-Do-Buffer"} = $WKRCD4_BinaryValues{"Do-Buffer"};
$WKRCD4_BinaryValues{"Ausfall-Di-Buffer"} = $WKRCD4_BinaryValues{"Di-Buffer"};
$WKRCD4_BinaryValues{"Ausfall-BetriebMode"} = $WKRCD4_BinaryValues{"Betriebszustaende"};

# Definition of the values that can be read / written
# with the relative address, number of bytes and
# fmat to be used in sprintf when formatting the value
# unp to be used in pack / unpack commands
# min / max for setting values
#
# ---- !! WARNING !! ----
# Some readings (marked with comment) might not be correct.
# DO NOT SET THEM UNLESS YOU KNOW WHAT YOU ARE DOING!
# ---- END OF WARNING ----
#
# Values with a * at the end of the menu-value are hidden on the
# control unit by defaults
#
my %frameReadings = (
 'Temp-Aussen'              => { addr => 0x000, bytes => 0x004, menu => '0.00', fmat => '%0.1f', unp => 'f<' },
 'Temp-Aussen-24h'          => { addr => 0x004, bytes => 0x004, menu => '0.01', fmat => '%0.1f', unp => 'f<' },
 'Temp-Aussen-1h'           => { addr => 0x008, bytes => 0x004, menu => '0.02', fmat => '%0.1f', unp => 'f<' },
 'Temp-Ruecklauf-Soll'      => { addr => 0x00C, bytes => 0x004, menu => '0.03', fmat => '%0.1f', unp => 'f<' },
 'Temp-Ruecklauf'           => { addr => 0x010, bytes => 0x004, menu => '0.04', fmat => '%0.1f', unp => 'f<' },
 'Temp-Vorlauf'             => { addr => 0x014, bytes => 0x004, menu => '0.05', fmat => '%0.1f', unp => 'f<' },
 'Temp-Raum'                => { addr => 0x018, bytes => 0x004, menu => '0.06', fmat => '%0.1f', unp => 'f<' },
 'Temp-Raum-1h'             => { addr => 0x01C, bytes => 0x004, menu => '0.07', fmat => '%0.1f', unp => 'f<' },
 'Temp-WQuelle-Ein'         => { addr => 0x020, bytes => 0x004, menu => '0.08', fmat => '%0.1f', unp => 'f<' },
 'Temp-WQuelle-Aus'         => { addr => 0x024, bytes => 0x004, menu => '0.09', fmat => '%0.1f', unp => 'f<' },
 'Temp-Verdampfer'          => { addr => 0x028, bytes => 0x004, menu => '0.10', fmat => '%0.1f', unp => 'f<' },
 'Temp-Kondensator'         => { addr => 0x02C, bytes => 0x004, menu => '0.11', fmat => '%0.1f', unp => 'f<' },
 'Ww-Temp'                  => { addr => 0x030, bytes => 0x004, menu => '2.03', fmat => '%0.1f', unp => 'f<' },
 'Zeit'                     => { addr => 0x034, bytes => 0x006, menu => '-.--', fmat=> '%4$02d.%5$02d.%6$02d %3$02d:%2$02d:%1$02d', unp => 'CCCCCC'},
 'Uhrzeit'                  => { addr => 0x034, bytes => 0x003, menu => '3.00', fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Datum'                    => { addr => 0x037, bytes => 0x003, menu => '3.01', fmat => '%02d.%02d.%02d', unp => 'CCC'},
 'Messbegin-Zeit'           => { addr => 0x03A, bytes => 0x003, menu => '3.02', fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Messbegin-Datum'          => { addr => 0x03D, bytes => 0x003, menu => '3.03', fmat => '%02d.%02d.%02d', unp => 'CCC' },
 'Hz-Messergebnis'          => { addr => 0x040, bytes => 0x004, menu => '3.04', fmat => '%0.1f', unp => 'f<' },
 'Ww-Messergebnis'          => { addr => 0x044, bytes => 0x004, menu => '3.05', fmat => '%0.1f', unp => 'f<' },
 'Mess-Reset'               => { addr => 0x048, bytes => 0x001, menu => '3.06', unp => 'C', min => 1, max => 1 },
 'KomprBeginn-Zeit'         => { addr => 0x049, bytes => 0x003, menu => '3.07*', fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'KomprBeginn-Datum'        => { addr => 0x04C, bytes => 0x003, menu => '3.08*', fmat => '%02d.%02d.%02d', unp => 'CCC' },
 'KomprBetrStunden'         => { addr => 0x04F, bytes => 0x004, menu => '3.09*', fmat => '%0.1f', unp => 'f<' },
 'Kompr-Mess-Reset'         => { addr => 0x053, bytes => 0x001, menu => '3.10*', unp => 'C', min => 1, max => 1 },
 'Unterbrechungen'          => { addr => 0x054, bytes => 0x001, menu => '4.00*', unp => 'B8' },
 'Warnung-Eingang'          => { addr => 0x055, bytes => 0x001, menu => '4.01*', unp => 'B8' },
 'Warnung-Ausgang'          => { addr => 0x056, bytes => 0x001, menu => '4.02*', unp => 'B8' },
 'Warnung-Sonstige'         => { addr => 0x057, bytes => 0x001, menu => '4.03*', unp => 'B8' },
 'Ausfaelle'                => { addr => 0x058, bytes => 0x001, menu => '4.04*', unp => 'B8' },
 'Fuehler-Ausfall'          => { addr => 0x059, bytes => 0x001, menu => '4.05*', unp => 'B8' },
 'Fuehler-KurzSchl'         => { addr => 0x05A, bytes => 0x001, menu => '4.06*', unp => 'B8' },
 'FuehlerZaehler0'          => { addr => 0x05B, bytes => 0x002, menu => '4.07*', unp => 'n' },
 'FuehlRaum-Ausfall'        => { addr => 0x05D, bytes => 0x001, menu => '4.08*', unp => 'B8' },
 'FuehlRaum-KurzSchl'       => { addr => 0x05E, bytes => 0x001, menu => '4.09*', unp => 'B8' },
 'FuehlRaum-Zaehler0'       => { addr => 0x05F, bytes => 0x002, menu => '4.10*', unp => 'n' },
 'Ausfall-Zeit'             => { addr => 0x061, bytes => 0x003, menu => '5.00', fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Ausfall-Datum'            => { addr => 0x064, bytes => 0x003, menu => '5.01', fmat => '%02d.%02d.%02d', unp => 'CCC' },
 'Ausfall-BetriebMode'      => { addr => 0x067, bytes => 0x001, menu => '5.02', unp => 'B8' },
 'Ausfall-Do-Buffer'        => { addr => 0x068, bytes => 0x001, menu => '5.03', unp => 'B8' },
 'Ausfall-Di-Buffer'        => { addr => 0x069, bytes => 0x001, menu => '5.04', unp => 'B8' },
 'Ausfall-FuehlAusfall'     => { addr => 0x06A, bytes => 0x001, menu => '5.05', unp => 'B8' },
 'Ausfall-FuehlKurzsch'     => { addr => 0x06B, bytes => 0x001, menu => '5.06', unp => 'B8' },
 'Ausfall-Temp-Aussen'      => { addr => 0x06C, bytes => 0x004, menu => '5.07', fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-WQu-Ein'     => { addr => 0x070, bytes => 0x004, menu => '5.08', fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-WQu-Aus'     => { addr => 0x074, bytes => 0x004, menu => '5.09', fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-Verdampfer'  => { addr => 0x078, bytes => 0x004, menu => '5.10', fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-Ruecklf'     => { addr => 0x07C, bytes => 0x004, menu => '5.11', fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-Vorlauf'     => { addr => 0x080, bytes => 0x004, menu => '5.12', fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-Kondensator' => { addr => 0x084, bytes => 0x004, menu => '5.13', fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-WWasser'     => { addr => 0x088, bytes => 0x004, menu => '5.14', fmat => '%0.1f', unp => 'f<' },
 'Ausfall-RaumAusfall'      => { addr => 0x08C, bytes => 0x001, menu => '5.15', unp => 'B8' },
 'Ausfall-RaumKurzsch'      => { addr => 0x08D, bytes => 0x001, menu => '5.16', unp => 'B8' },
 'Ausfall-Temp-Raum'        => { addr => 0x08E, bytes => 0x004, menu => '5.17', fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Reset'            => { addr => 0x092, bytes => 0x001, menu => '5.18', unp => 'C', min => 1, max => 1 },
 'Kennwort'                 => { addr => 0x093, bytes => 0x001, menu => '6.00', unp => 'C', min => 0, max => 255 },
 'Werkseinstellung'         => { addr => 0x094, bytes => 0x001, menu => '6.01', unp => 'C', min => 1, max => 1 },
 'ResetAnforderung'         => { addr => 0x095, bytes => 0x001, menu => '6.03', unp => 'C', min => 1, max => 1 },
 'Betriebszustaende'        => { addr => 0x096, bytes => 0x001, menu => '8.00*', unp => 'B8' },
 'Do-Buffer'                => { addr => 0x097, bytes => 0x001, menu => '8.01*', unp => 'B8' },
 'Di-Buffer'                => { addr => 0x098, bytes => 0x001, menu => '8.02*', unp => 'B8' },
 'Status-Gesamt'            => { addr => 0x099, bytes => 0x002, menu => '8.03*', unp => 'n' },
 'Status-Verriegel'         => { addr => 0x09B, bytes => 0x002, menu => '8.04*', unp => 'n' },
 'Status-Heizung'           => { addr => 0x09D, bytes => 0x002, menu => '8.05*', unp => 'n' },
 'Status-Stufe2'            => { addr => 0x09F, bytes => 0x002, menu => '8.06*', unp => 'n' },
 'Status-Wasser'            => { addr => 0x0A1, bytes => 0x002, menu => '8.07*', unp => 'n' },
 'Status-WPumpe'            => { addr => 0x0A3, bytes => 0x002, menu => '8.08*', unp => 'n' },
 'Mode-Heizung'             => { addr => 0x0A5, bytes => 0x001, menu => '8.09*', unp => 'B8' },
 'Hz'                       => { addr => 0x0A5, bytes => 0x001, menu => '-.--', unp => 'b' },
 'Mode-Wasser'              => { addr => 0x0A6, bytes => 0x001, menu => '8.10*', unp => 'B8' },
 'Ww'                       => { addr => 0x0A6, bytes => 0x001, menu => '-.--', unp => 'b' },
 'Versions-Datum'           => { addr => 0x0A7, bytes => 0x003, menu => '9.01', fmat => '%02d.%02d.%02d', unp => 'CCC' },
 'CPU-Boot-Zeit'            => { addr => 0x0AA, bytes => 0x003, menu => '9.02', fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'CPU-Boot-Datum'           => { addr => 0x0AD, bytes => 0x003, menu => '9.03', fmat => '%02d.%02d.%02d', unp => 'CCC' },
 'CRC-Summe'                => { addr => 0x0B0, bytes => 0x002, menu => '9.05*', unp => 'n' },
 'Neu-Start'                => { addr => 0x0B2, bytes => 0x001, menu => '9.06*', unp => 'C' },
 'Hz-Abschaltung'           => { addr => 0x0B3, bytes => 0x001, menu => '1.00', unp => 'C', min => 0, max => 1 },
 'Hz-Temp-Einsatz'          => { addr => 0x0B4, bytes => 0x004, menu => '1.01', fmat => '%0.1f', unp => 'f<', min => 10.0, max => 30.0 },
 'Hz-Temp-BasisSoll'        => { addr => 0x0B8, bytes => 0x004, menu => '1.02', fmat => '%0.1f', unp => 'f<', min => 15.0, max => 50.0 },
 'Hz-KlSteilheit'           => { addr => 0x0BC, bytes => 0x004, menu => '1.03', fmat => '%0.1f', unp => 'f<', min => 0.0, max => 100.0 },
 'Hz-SchnellAufhz'          => { addr => 0x0C0, bytes => 0x001, menu => '1.04', unp => 'C', min => 0, max => 1 },
 'Hz-Zeit-Ein'              => { addr => 0x0C1, bytes => 0x003, menu => '1.05', fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Hz-Zeit-Aus'              => { addr => 0x0C4, bytes => 0x003, menu => '1.06', fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Hz-Anhebung-Ein'          => { addr => 0x0C7, bytes => 0x003, menu => '1.07', fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Hz-Anhebung-Aus'          => { addr => 0x0CA, bytes => 0x003, menu => '1.08', fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Hz-Temp-RaumSoll'         => { addr => 0x0CD, bytes => 0x004, menu => '1.09', fmat => '%0.1f', unp => 'f<', min => 15.0, max => 30.0 },
 'Hz-Raum-Einfluss'         => { addr => 0x0D1, bytes => 0x001, menu => '1.10*', unp => 'C', min => 0, max => 200 },
 'Hz-Ext-Anhebung'          => { addr => 0x0D2, bytes => 0x004, menu => '1.11*', fmat => '%0.1f', unp => 'f<', min => -5.0, max => 5.0 },
 'Hz-Begrenzung'            => { addr => 0x0D6, bytes => 0x004, menu => '1.12*', fmat => '%0.1f', unp => 'f<', min => 10.0, max => 50.0 },
 'Hz-Stufe2-Begrenzung'     => { addr => 0x0DA, bytes => 0x004, menu => '1.13*', fmat => '%0.1f', unp => 'f<', min => 10.0, max => 60.0 },
 'Hz-Hysterese'             => { addr => 0x0DE, bytes => 0x004, menu => '1.14*', fmat => '%0.1f', unp => 'f<', min => 1.0, max => 3.0 },
 'Hz-PumpenNachl'           => { addr => 0x0E2, bytes => 0x001, menu => '1.15*', unp => 'C', min => 0, max => 20 },
 'Ww-Abschaltung'           => { addr => 0x0E3, bytes => 0x001, menu => '2.00', unp => 'C', min => 0, max => 1 },
 'Ww-Zeit-Ein'              => { addr => 0x0E4, bytes => 0x003, menu => '2.01', fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Ww-Zeit-Aus'              => { addr => 0x0E7, bytes => 0x003, menu => '2.02', fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Ww-Temp-Soll'             => { addr => 0x0EA, bytes => 0x004, menu => '2.04', fmat => '%0.1f', unp => 'f<', min => 20.0, max => 55.0 },
 'Ww-Becken-Temp-Soll'      => { addr => 0x0EE, bytes => 0x004, menu => '2.05', fmat => '%0.1f', unp => 'f<', min => 20.0, max => 35.0 },
 'Ww-Hysterese'             => { addr => 0x0F2, bytes => 0x004, menu => '2.06', fmat => '%0.1f', unp => 'f<', min => 5.0, max => 10.0 },
 'Ww-Becken-Hysterese'      => { addr => 0x0F6, bytes => 0x004, menu => '2.07*', fmat => '%0.1f', unp => 'f<', min => 0.5, max => 5.0 },
 'Unterdr-Warnung-Eingang'  => { addr => 0x0FA, bytes => 0x001, menu => '4.11*', unp => 'B8' },
 'Unterdr-Warnung-Ausgang'  => { addr => 0x0FB, bytes => 0x001, menu => '4.12*', unp => 'B8' },
 'Unterdr-Warnung-Sonstige' => { addr => 0x0FC, bytes => 0x001, menu => '4.13*', unp => 'B8' },
 'Betriebs-Mode'            => { addr => 0x0FD, bytes => 0x003, menu => '6.02', fmat => '%d.%d.%d', unp => 'CCC' },
 'Modem-Klingelzeichen'     => { addr => 0x100, bytes => 0x001, menu => '6.04', unp => 'C', min => 1, max => 6 },
 'Fremdzugriff'             => { addr => 0x101, bytes => 0x001, menu => '6.05', unp => 'C', min => 0, max => 1 },
 'Schluesselnummer'         => { addr => 0x102, bytes => 0x001, menu => '6.06', unp => 'C', min => 0, max => 255 },
 'Hz-Ext-Freigabe'          => { addr => 0x103, bytes => 0x001, menu => '6.07*', unp => 'C', min => 0, max => 1 },
 'Hz-Ext-TempRueckl-Soll'   => { addr => 0x104, bytes => 0x004, menu => '6.08*', fmat => '%0.1f', unp => 'f<', min => 0.0, max => 30.0 },
 'St2-Temp-QAus-Min'        => { addr => 0x108, bytes => 0x004, menu => '6.09*', fmat => '%0.1f', unp => 'f<', min => -25.0, max => 20.0 },
 'St2-Temp-Verdampfer-Min'  => { addr => 0x10C, bytes => 0x004, menu => '6.10*', fmat => '%0.1f', unp => 'f<', min => -25.0, max => 20.0 },
 'Estrich-Aufhz'            => { addr => 0x110, bytes => 0x001, menu => '6.11*', unp => 'C', min => 0, max => 1 },
 'Hz-Ext-Steuerung'         => { addr => 0x111, bytes => 0x001, menu => '6.12*', unp => 'B8' },
 'St2-bei-EvuAbsch'         => { addr => 0x112, bytes => 0x001, menu => '6.13*', unp => 'C', min => 0, max => 1 },
 'Freigabe-Beckenwasser'    => { addr => 0x113, bytes => 0x001, menu => '6.14*', unp => 'C', min => 0, max => 1 },
 'Do-Handkanal'             => { addr => 0x114, bytes => 0x001, menu => '7.00*', unp => 'C', min => 0, max => 8 },
 'Do-Handkanal-Ein'         => { addr => 0x115, bytes => 0x001, menu => '7.01*', unp => 'C', min => 0, max => 1 },
 'AnalogKorrFaktor'         => { addr => 0x116, bytes => 0x004, menu => '9.04*', fmat => '%0.4f', unp => 'f<', min => 0.8000, max => 1.2000 },
 'Run-Flag'                 => { addr => 0x11A, bytes => 0x001, menu => '9.07*', unp => 'C', min => 0, max => 1 },
);

#
# FHEM module initialize
# defines the functions to be called from FHEM
#########################################################################
sub WKRCD4_Initialize($)
{
    my ($hash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    $hash->{ReadFn}  = "WKRCD4_Read";
    $hash->{ReadyFn} = "WKRCD4_Ready";
    $hash->{DefFn}   = "WKRCD4_Define";
    $hash->{UndefFn} = "WKRCD4_Undef";
    $hash->{SetFn}   = "WKRCD4_Set";
    $hash->{GetFn}   = "WKRCD4_Get";
    $hash->{AttrList} = "enableAdvancedMode:0,1 do_not_notify:1,0 disable:0,1 " . $readingFnAttributes;
    $hash->{AttrFn} = "WKRCD4_Attr";
}

#
# Define command
# Init internal values, open device,
# set internal timer to send read command / wakeup.
#########################################################################                                   #
sub WKRCD4_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);

    return "wrong syntax: define <name> WKRCD4 [devicename\@speed|none] [interval]"
      if (@a < 3);

    DevIo_CloseDev($hash);
    my $name = $a[0];
    my $dev  = $a[2];
    my $interval  = 60;

    if ($dev eq "none") {
        Log3 undef, 1, "$name: Device is none, commands will be echoed only.";
        return undef;
    }

    if(int(@a) == 4) {
        $interval = $a[3];

        if ($interval == 0) {
          Log3 undef, 1, "$name: Interval is 0, automatic requests disabled.";
        }
        elsif ($interval < 4)
        {
          return "Error: Interval has to be > 3 or 0 (for no auto-requests), default is 60."
        }
    }

    $hash->{buffer}             = "";

    $hash->{DeviceName}         = $dev;
    $hash->{INTERVAL}           = $interval;

    $hash->{SerialRequests}     = 0;
    $hash->{SerialGoodReads}    = 0;
    $hash->{SerialBadReads}     = 0;

    # Send wakeup string (read 2 values preceeded with AT)
    $hash->{LastRequestAdr}     = -1;
    $hash->{LastRequestLen}     = 0;
    $hash->{LastRequest}        = gettimeofday();
    my $ret = DevIo_OpenDev( $hash, 0, "WKRCD4_Wakeup" );

    # Initial read after 3 secs, there timer is set to interval for update and wakeup
    if($interval != 0)
    {
      InternalTimer(gettimeofday()+3, "WKRCD4_GetUpdate", $hash, 0);
    }

    return $ret;
}

#
# Undefine command, called when the device is deleted
#########################################################
sub WKRCD4_Undef($$)
{
    my ( $hash, $arg ) = @_;
    DevIo_CloseDev($hash);
    RemoveInternalTimer($hash);
    return undef;
}

#
# Encode the data to be sent to the device (0x10 gets doubled)
#################################################################
sub Encode10 (@) {
    my @a = ();
    for my $byte (@_) {
        push @a, $byte;
        push @a, $byte if $byte == 0x10;
    }
    return @a;
}

#
# Create a command for the heat pump as byte array
######################################################
sub WPCMD($$$$;@)
{
    my ($hash, $cmd, $addr, $len, @value ) = @_;
    my $name = $hash->{NAME};
    my @frame = ();

    if ($cmd eq "read") {
        @frame = (0x01, 0x15, Encode10($addr>>8, $addr%256), Encode10($len>>8, $len%256));
    } elsif ($cmd eq "write") {
        @frame = (0x01, 0x13, Encode10($addr>>8, $addr%256), Encode10(@value));
    } elsif ($cmd eq "dateTimeSync") {
        @frame = (0x01, 0x14, 0x00, 0x00, Encode10(@value));
    } else {
        Log3 $name, 3, "$name: Undefined command ($cmd) in WPCMD";
        return 0;
    }

    my $crc = CRC16(@frame);
    return (0xff, 0x10, 0x02, @frame, 0x10, 0x03, $crc >> 8, $crc % 256, 0xff);
}

#
# FHEM-Get command
######################
sub WKRCD4_Get($@)
{
    my ( $hash, @a ) = @_;
    return "\"get WKRCD4\" needs at least an argument" if ( @a < 2 );

    my $name = shift @a;
    my $attr = shift @a;
    my $arg = join("", @a);
    my $searchWord = "menuEntry";

    if((!$WKRCD4_gets{$attr}) && substr($attr, 0, length($searchWord)) ne $searchWord) {
        my @cList = keys %WKRCD4_gets;

        return "Unknown argument $attr, choose one of " . join(":noArg ", @cList, '') . " menuEntry:textField menuEntryHidden:textField";
    }

    return "Error: Device is disabled." if(IsDisabled($name));

    my $properties;

    if($attr eq "menuEntry" || $attr eq "menuEntryHidden")
    {
      # User wants to get the menu entry or check whether it's hidden or not
        $properties = $frameReadings{$arg};

        if(!$properties) {
            return "No entry in frameReadings found for \"$arg\"";
        }

        my $menuEntry = substr($properties->{menu}, 0, 4);
        my $menuEntryHiddenRaw = substr($properties->{menu}, -1);

        # An asterisk means that it's hidden by default
        my $menuEntryHidden = $menuEntryHiddenRaw eq "*";

        if($attr eq "menuEntry")
        {
            return $menuEntry;
        }
        else
        {
            return $menuEntryHidden ? 1 : 0;
        }
    }
    else
    {
      # Get hash pointer for the attribute requested from the global hash
        $properties = $frameReadings{$WKRCD4_gets{$attr}};
        if(!$properties) {
            return "No entry in frameReadings found for $attr";
        }
    }

    # Get details about the attribute requested from its hash
    my $addr  = $properties->{addr};
    my $bytes = $properties->{bytes};
    Log3 $name, 4, sprintf ("$name: Get - Reading %02x bytes starting from %02x for $attr", $bytes, $addr);

    # Create command for heat pump
    my $cmd = pack('C*', WPCMD($hash, 'read', $addr, $bytes));

    # Set internal variables to track what is happending
    $hash->{LastRequestAdr} = $addr;
    $hash->{LastRequestLen} = $bytes;
    $hash->{LastRequest}    = gettimeofday();
    $hash->{SerialRequests}++;

    Log3 $name, 4, "$name: Get - Called DevIo_SimpleWrite: " . unpack ('H*', $cmd);
    DevIo_SimpleWrite( $hash, $cmd , 0 );

    return sprintf ("Reading %02x bytes starting from %02x", $bytes, $addr);
}

#
# FHEM-Set command
######################
sub WKRCD4_Set($@)
{
    my ( $hash, @a ) = @_;
    return "\"set WKRCD4\" needs at least an argument" if ( @a < 2 );
    
    my $name = shift @a;
    my $attr = shift @a;
    my $arg = join("", @a);

    if(!defined($WKRCD4_sets{$attr}) && $attr ne "dateTimeSync" && $attr ne "statusRequest") {
        my @cList = keys %WKRCD4_sets;
        my $finalReturn;

        foreach my $val (@cList)
        {
            my $current = $frameReadings{$val};
            $finalReturn .= $val;

            if(($current->{unp} eq "C" || $current->{unp} eq "n") && ($current->{min} == 0 && $current->{max} == 1))
            {
                # Bool value, only 0 and 1 for set available
                $finalReturn .= ":0,1";
            }
	    elsif(($current->{unp} eq "C" || $current->{unp} eq "n") && ($current->{min} == $current->{max}))
	    {
	        # One-option field (no argument)
	        $finalReturn .= ":noArg";
	    }
	    elsif($current->{unp} eq "C" && $current->{min} == 0 && $current->{max} == 8)
	    {
		$finalReturn .= ":0_Deaktiviert";
                for(my $i = 0; $i < 8; $i++)
                {
                    $finalReturn .= "," . ($i + 1) . "_" . $WKRCD4_BinaryValues{"Do-Buffer"}[8 - ($i + 1)];
                }
	    }
	    else
            {
                $finalReturn .= ":textField";
            }

            $finalReturn .= " ";
        }

        return "Unknown argument $attr, choose one of dateTimeSync:noArg statusRequest:noArg " . $finalReturn;
    }

    return "Error: Device is disabled." if(IsDisabled($name));

    my $vp;
    my @value;
    my $isSpecialValue = 0;
    my $cmd;
    my $addr;
    my $bytes;
    my $unp;

    my $properties;
    if(defined($WKRCD4_sets{$attr}))
    {
       # Get hash pointer for the attribute requested from the global hash
       $properties = $frameReadings{$WKRCD4_sets{$attr}};
    }

    if(!$properties) {
      if($attr eq "dateTimeSync")
      {
        # User wants to sync time/date
        $addr = 0;
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);

        # SS:MM:HH
        my $time = pack('C', $sec) . pack('C', $min) . pack('C', $hour);
        # DD.MM.YY
        my $date = pack('C', $mday) . pack('C', $mon + 1) . pack('C', sprintf("%02d", $year % 100));
        my $result = $time . $date;

        $vp = $result;
        @value = unpack('C*', $result);
        $cmd = pack('C*', WPCMD(undef, $attr, 0x0000, 0, @value));
        $bytes = 0x06;

        $isSpecialValue = 1;
      }
      elsif($attr eq "statusRequest")
      {
        # Request without adding new interval
        WKRCD4_GetUpdate($hash, 0);
        return;
      }
      else
      {
        return "Error: No entry in frameReadings found for $attr";
      }
    }

    if($attr ne "dateTimeSync")
    {
      # User does not want to sync time/date
        # Get details about the attribute requested from its hash
        $addr = $properties->{addr};
        $bytes = $properties->{bytes};
        my $min = $properties->{min};
        my $max = $properties->{max};
        $unp = $properties->{unp};
	
	if($attr eq "Do-Handkanal")
        {
          $arg = substr($arg, 0, 1);
        }
	
	# Only set if it's not binary
	if(defined($properties->{min}) && defined($properties->{max}))
	{
	  if($min != $max)
	  {
	    $arg =~ s/\,/./g;
            return "Error: A numeric value between $min and $max is expected, got $arg instead."
                if(($arg !~ m/^-?[\d.]+$/ || $arg < $min || $arg > $max) && ($unp ne "B8" && $unp ne "CCC"));
          }
	  else
	  {
	    $arg = $min;
	  }
	}
	
        # If it's a binary value, check for validity
        if($unp eq "B8" && $arg !~ /\b[01]{8}\b/)
        {
          return "Error: Binary values have to be 8 characters long and may only contain 0 and 1.";
        }

        # Is it a date/time or a special value?
        elsif($unp eq "CCC" && $properties->{fmat})
        {
          $isSpecialValue = 1;

          my $splitter;
          my $fmat = $properties->{fmat};
          my @splitted;
          my $result;

          # Is it a time?
          if($arg =~ /(0[0-9]|1[0-9]|2[0-4]):[0-5][0-9]:[0-5][0-9]/ && $fmat eq '%3$02d:%2$02d:%1$02d')
          {
            if($addr != 0x034)
            {
              $splitter = ':';
              @splitted = split($splitter, $arg);
              # Reverse the array: Time stored as SS:MM:HH
              @splitted = reverse @splitted;
            }
            else
            {
              return "Error: Setting the actual time/date values is not supported.";
            }
          }
          # Is it a date?
          elsif($arg =~ /(3[01]|[12][0-9]|0[1-9])\.(1[012]|0[1-9])\.(\d{2})/ && $fmat eq '%02d.%02d.%02d')
          {
            if($addr != 0x037 && $addr != 0x034)
            {
              my $calcDate = Time::Piece->strptime($arg,"%d.%m.%y")->strftime("%d.%m.%y");

              if($calcDate eq $arg)
              {
                $splitter = '\.';
                @splitted = split($splitter, $arg);
              }
              else
              {
                return "Error: The given date is invalid.";
              }
            }
            else
            {
              return "Error: Setting the actual time/date values is not supported.";
            }
          }
          # Is it a Betriebs-Mode-change?
          elsif($arg =~ /[1-5]\.[1-5]\.[12]/ && $addr == 0x0FD)
          {
            $splitter = '\.';
            @splitted = split($splitter, $arg);
          }
          # Nope, it's nothing.
          else
          {
            return "Error: Field doesn't match any supported data type or input isn't valid for this operation.";
          }

          foreach my $current(@splitted)
          {
            $result .= pack('C', $current);
          }

          $vp = $result;
          @value = unpack('C*', $vp);
        }
        else
        {
          # Convert string to value needed for command
          $vp    = pack($unp, $arg);
          @value = unpack ('C*', $vp);
        }

	if($unp ne "CCC")
	{
          Log3 $name, 4, sprintf ("$name: Set - Will write $attr: %02x bytes starting from %02x with %s (%s) packed with $unp", $bytes, $addr, unpack ('H*', $vp), unpack ($unp, $vp));
        }
	else
	{
	  Log3 $name, 4, sprintf ("$name: Set - Will write time/date $attr: %02x bytes starting from %02x with %s packed with $unp", $bytes, $addr, unpack ('H*', $vp));
	}
	
	$cmd = pack('C*', WPCMD($hash, 'write', $addr, $bytes, @value));
    }

    # Set internal variables to track the situation
    $hash->{LastRequestAdr} = $addr;
    $hash->{LastRequestLen} = $bytes;
    $hash->{LastRequest}    = gettimeofday();
    $hash->{SerialRequests}++;
    Log3 $name, 4, "Set - Called DevIo_SimpleWrite: " . unpack ('H*', $cmd);
    DevIo_SimpleWrite( $hash, $cmd , 0 );

    if($isSpecialValue)
    {
      return sprintf ("Wrote %02x bytes starting from %02x with %s", $bytes, $addr, unpack ('H*', $vp));
    }
    else
    {
      return sprintf ("Wrote %02x bytes starting from %02x with %s (%s)", $bytes, $addr, unpack ('H*', $vp), unpack ($unp, $vp));
    }
}

#########################################################################
# Called from the global loop, when the select for hash->{FD} reports data
sub WKRCD4_Read($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # Read from serial device
    my $buf = DevIo_SimpleRead($hash);
    return "" if ( !defined($buf) );

    $hash->{buffer} .= $buf;
    Log3 $name, 5, "$name: Read - Buffer content: " . unpack ('H*', $hash->{buffer});

    # Do we have a full frame already?
    if ( $hash->{buffer} !~ /\x16\x10\x02(.{2})(.*)\x10\x03(.{2})\x16(.*)/s )
    {
        Log3 $name, 5, "$name: Read - No match: " . unpack ('H*', $hash->{buffer});
        return "";
    }
    my $msg    = unpack ('H*', $1);
    my @aframe = unpack ('C*', $1 . $2);
    my $crc    = unpack ('S>', $3);
    my $rest   = $4;

    # Is the frame really complete?
    if(($msg ne "0011") && (@aframe < $hash->{LastRequestLen}))
    {
        return "";
    }
    
    $hash->{buffer} = $rest;
    Log3 $name, 4, "$name: Read - Match: $msg CRC $crc";
    Log3 $name, 5, "$name: Read - Frame is " . unpack ('H*', pack ('C*', @aframe)) . ", Rest " . unpack ('H*', $rest);

    # Calculate CRC and compare with CRC from read
    my $crc2 = CRC16(@aframe);
    if ($crc != $crc2) {
        Log3 $name, 3, "$name: Read - CRC invalid (got $crc, calculated $crc2)";
        Log3 $name, 4, "$name: Read - Frame was " . unpack ('H*', pack ('C*', @aframe));
        $hash->{SerialBadReads} ++;
        @aframe = ();
        return "";
    };

    Log3 $name, 4, "$name: Read - CRC valid.";
    $hash->{SerialGoodReads}++;

    # Reply to read request?
    if ($msg eq "0017") {
        my @data;
        for(my $i=0, my $offset=2; $offset <= $#aframe; $offset++, $i++)
        {
            # Remove duplicate 0x10 (frames are encoded that way)
            if (($aframe[$offset] == 16) && ($aframe[$offset + 1] == 16)) { $offset++; }
            $data[$i] = $aframe[$offset];
        }
        Log3 $name, 4, "$name: Read - Parse with relative request started (Address: " . $hash->{LastRequestAdr} . ", length: " . $hash->{LastRequestLen} . ")";
        # Extract values from data
        parseReadings($hash, @data);
    } elsif ($msg eq "0011") {
        # Reply to write
    } else {
        Log3 $name, 3, "$name: Read - Got unknown message type " . $msg . " in " . $hash->{buffer};
    }
    @aframe = ();
    return "";
}

#
# Copied from other FHEM modules
#########################################################################
sub WKRCD4_Ready($)
{
    my ($hash) = @_;

    return DevIo_OpenDev( $hash, 1, undef )
      if ( $hash->{STATE} eq "disconnected" );

    # This is relevant for Windows/USB only
    my $po = $hash->{USBDev};
    my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;
    return ( $InBytes > 0 );
}

#
# Send wakeup string (Control unit doesn't respond without that)
###########################################################
sub WKRCD4_Wakeup($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    $hash->{SerialRequests}++;

    $hash->{LastRequestAdr} = -1;
    $hash->{LastRequestLen} = 0;
    $hash->{LastRequest}    = gettimeofday();

    # my $cmd = "41540D10020115000000041003FE0310020115003000041003FDC3100201150034000410037D90";
    
    my $cmd = "41540D"; # AT and carriage return
    DevIo_SimpleWrite( $hash, $cmd , 1 );

    Log3 $name, 5, "$name: Sent wakeup string: " . $cmd;
    return undef;
}

#
# Request new data from WP
#############################
sub WKRCD4_GetUpdate($;$)
{
    my ($hash, $noInterval) = @_;
    my $name = $hash->{NAME};

    # Set time for new request every {INTERVAL} seconds
    if(!$noInterval)
    {
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "WKRCD4_GetUpdate", $hash, 1);
      InternalTimer(gettimeofday()+$hash->{INTERVAL}/2, "WKRCD4_Wakeup", $hash, 1);
    }

    $hash->{SerialRequests}++;

    my $cmd = pack('C*', WPCMD($hash, 'read', 0, 0x011B));
    $hash->{LastRequestAdr} = 0;
    $hash->{LastRequestLen} = 0x011B;
    $hash->{LastRequest}    = gettimeofday();
    DevIo_SimpleWrite( $hash, $cmd , 0 );

    Log3 $name, 5, "$name: GetUpdate - Called DevIo_SimpleWrite: " . unpack ('H*', $cmd);

    return 1;
}

#
# Executed when an attribute is set
########################################
sub WKRCD4_Attr($$$$)
{
  my ( $cmd, $name, $attrName, $attrValue ) = @_;
  my $hash = $defs{$name};
  
  if ($cmd eq "set") {
    # Advanced mode: Enables the advanced readings
    if ($attrName eq "enableAdvancedMode") {
      if($attrValue == 0 || $attrValue == 1)
      {
        advancedMode($attrValue);
      }
      else
      {
        return "Error: Valid values are 0 and 1.";
      }
    }
    elsif ($attrName eq "disable")
    { 
      if($attrValue) {
        DevIo_CloseDev($hash);
        $hash->{buffer} = "";
      }
      else
      {
        $hash->{buffer} = "";
        DevIo_OpenDev( $hash, 0, "WKRCD4_Wakeup" );
      }
    }
  }
  else
  {
    if ($attrName eq "enableAdvancedMode") {
      advancedMode(0);
    }
    elsif ($attrName eq "disable") {
      DevIo_OpenDev( $hash, 0, "WKRCD4_Wakeup" );
      $hash->{buffer} = "";
    }
  }
  
  return undef;
}

#
# Enables/Disables advanced mode based on parameter
#######################################################
sub advancedMode($)
{
  my ($action) = @_;
  
  if($action == 0)
  {
    # Restore old sets and gets
    %WKRCD4_sets = %WKRCD4_sets_default;
    %WKRCD4_gets = %WKRCD4_sets;
    # Merge user gets
    %WKRCD4_gets = (%WKRCD4_gets, %WKRCD4_gets_more);
  }
  elsif($action == 1)
  {
    # Merge the hashes
    %WKRCD4_sets = (%WKRCD4_sets, %WKRCD4_advanced);
    %WKRCD4_gets = %WKRCD4_sets;
    # Merge user gets
    %WKRCD4_gets = (%WKRCD4_gets, %WKRCD4_gets_more);
  }
  
  return $action;
}

#
# Calculate CRC16 for communication with the heat pump
#########################################################
sub CRC16
{
    my $CRC = 0;
    my $POLY  = 0x800500;

    for my $byte (@_, 0, 0) {
        $CRC |= $byte;
        for (0 .. 7) {
            $CRC <<= 1;
            if ($CRC & 0x1000000) { $CRC ^= $POLY; }
            $CRC &= 0xffffff;
        }
    }
    return $CRC >> 8;
}

#
# Get values after data read
###############################
sub parseReadings
{
    my ($hash, @data) = @_;
    my $name = $hash->{NAME};

    my $reqStart = $hash->{LastRequestAdr};
    my $reqLen   = $hash->{LastRequestLen};

    # Got enough bytes?
    if (@data >= $reqLen)
    {
        readingsBeginUpdate($hash);
        # Go trough all possible readings
        while (my ($reading, $property) = each(%frameReadings))
        {
            my $addr  = $property->{addr};
            my $bytes = $property->{bytes};

            # Is the reading inside the data?
            if (($addr >= $reqStart) &&
                ($addr + $bytes <= $reqStart + $reqLen))
            {
                my $Idx = $addr - $reqStart;
                # Get relevant slice from data array
                my @slice = @data[$Idx .. $Idx + $bytes - 1];

                # Convert according to rules in global hash or defaults
                my $pack   = ($property->{pack}) ? $property->{pack} : 'C*';
                my $unpack = ($property->{unp})  ? $property->{unp}  : 'H*';
                my $fmat   = ($property->{fmat}) ? $property->{fmat} : '%s';
                my $value = sprintf ($fmat, unpack ($unpack, pack ($pack, @slice)));

                readingsBulkUpdate( $hash, $reading, $value );
                Log3 $name, 4, "$name: Parse - Set $reading to $value" if (@data <= 20);
            }
        }

        # Set the binary reading-messages to "Msg-*" fields
        setBinaryReadings($hash);
        readingsEndUpdate( $hash, 1 );
    }
    else
    {
        Log3 $name, 5, "$name: Parse - Date lenght smaller than requested ($reqLen) : " . unpack ('H*', pack ('C*', @data));
        return 0;
    }
}

#
# Creates "Msg-*" readings for binary messages
##################################################
sub setBinaryReadings($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # Check for every binary value field in hash
  foreach my $key (keys %WKRCD4_BinaryValues)
  {
    my $result = "";

    # Go trough all messages for $key
    for(my $i = 0; $i < scalar(@{$WKRCD4_BinaryValues{$key}}); $i++)
    {
      if(substr(ReadingsVal($name, $key, 0), $i, 1))
      {
        # Character is 1, add corresponding string
        if($WKRCD4_BinaryValues{$key}[$i] ne "")
        {
          $result .= $WKRCD4_BinaryValues{$key}[$i] . ", ";
        }
      }
    }

    my $newValue = trim(substr($result, 0, -2));

    # Only create reading if it's not 00000000
    if($newValue ne "")
    {
      readingsBulkUpdate($hash, "Msg-" . $key, $newValue);
    }
    else
    {
      # Delete reading if it's completely empty
      readingsDelete($hash, "Msg-" . $key)
    }
  }
}

1;




=pod
=item device
=item summary Module for communicating with the Waterkotte Resümat CD4

=begin html

 <a name="WKRCD4"></a>
 <h3>WKRCD4</h3>
 This module interacts with the Waterkotte Resümat CD4.

 <ul><br>
  <a name="WKRCD4_Define"></a>
  <b>Define</b>
  <ul> 
   <code>define &lt;name&gt; WKRCD4 &lt;device@baudrate&gt; &lt;interval&gt;</code><br>
   <br>
   Example: <code>define Heating WKRCD4 /dev/ttyUSB0@9600 60</code>
 </ul><br>

 <ul><br>
  <a name="WKRCD4_Attr"></a>
  <b>Attributes</b>
  <ul>
   <li>enableAdvancedMode<br><br>
     Enables or disables the advanced sets.<br>
     0 -> Disabled<br>
     1 -> Enabled</li>
    <li>disable<br><br>
    Enables or disables the device (closes the connection).</li>
  </ul>
 </ul> 

 <ul><br>
  <a name="WKRCD4_Set"></a>
  <b>Set</b>
  <ul>
   <li>dateTimeSync<br>
     Sends the server date and time to the Resümat controller.<br></li>
   <li>statusRequest<br>
     Manually requests every reading from the heating controller.</li>
  </ul>
 </ul> 

 <ul><br>
  <a name="WKRCD4_Get"></a>
  <b>Get</b>
  <ul>
   <li>menuEntry &lt;reading&gt;<br>
     Returns the menu entry number on the Resümat controller of a reading.<br></li>

   <li>menuEntryHidden &lt;reading&gt;<br>
     Returns 1 if the entry is hidden by default, 0 if not.<br></li>
  </ul>
 </ul>
 
=end html

=cut

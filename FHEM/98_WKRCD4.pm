#########################################################################
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
#       Abfrage-Bytes auf 0x122 verringert (ansonsten zu viel für SW-Version 8011: max. ~150)
#       Mehrere Get- und Set-Abfragen hinzugefügt
#       Min-/Max-Werte bei allen sets hinzugefügt
#       "Status"-Reading entfernt (kann aber unten aktiviert werden, einfach Kommentar-# entfernen)
#       Wakeup-Command geändert, als Nebeneffekt wird die Aussentemperatur öfters abgefragt
#       WARNING bezüglich set hinzugefügt
#
# ---- !! WARNING !! ----
# This module could destroy your heating if something goes extremely wrong!
# Be careful, especially with set commands. Min/max values MIGHT NOT be correct for your control unit.
# ---- END OF WARNING ----

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Encode qw(decode encode);

#
# list of Readings / values that can explicitely be requested
# from the WP with the GET command
my %WKRCD4_gets = (
    "Hz-KlSteilheit" => "Hz-KlSteilheit",
    "Hz-Temp-BasisSoll" => "Hz-Temp-BasisSoll",
    "Hz-Temp-Einsatz" => "Hz-Temp-Einsatz",
    "Hz-Temp-RaumSoll" => "Hz-Temp-RaumSoll",
    "Ww-Temp-Soll" => "Ww-Temp-Soll",
    "Hz-Abschaltung" => "Hz-Abschaltung",
    "Ww-Abschaltung" => "Ww-Abschaltung",
    # ---- Values work but do not need to be changed often/normally ----
    # ---- Just remove the # if you need them ----
    # "Ww-Becken-Temp-Soll" => "Ww-Becken-Temp-Soll",
    # "Ww-Hysterese" => "Ww-Hysterese",
    # "Ww-Becken-Hysterese" => "Ww-Becken-Hysterese",
    # "Kennwort" => "Kennwort",
    # "Modem-Klingelzeit" => "Modem-Klingelzeit",
    # "Fremdzugriff" => "Fremdzugriff",
    # "Schluesselnummer" => "Schluesselnummer",
);

# list of Readings / values that can be written to the WP
my %WKRCD4_sets = (
    "Hz-KlSteilheit" => "Hz-KlSteilheit",
    "Hz-Temp-BasisSoll" => "Hz-Temp-BasisSoll",
    "Hz-Temp-Einsatz" => "Hz-Temp-Einsatz",
    "Hz-Temp-RaumSoll" => "Hz-Temp-RaumSoll",
    "Ww-Temp-Soll" => "Ww-Temp-Soll",
    "Hz-Abschaltung" => "Hz-Abschaltung",
    "Ww-Abschaltung" => "Ww-Abschaltung",
    # ---- Values work but do not need to be changed often/normally ----
    # ---- Just remove the # if you need them ----
    # "Ww-Becken-Temp-Soll" => "Ww-Becken-Temp-Soll",
    # "Ww-Hysterese" => "Ww-Hysterese",
    # "Ww-Becken-Hysterese" => "Ww-Becken-Hysterese",
    # "Kennwort" => "Kennwort",
    # "Modem-Klingelzeit" => "Modem-Klingelzeit",
    # "Fremdzugriff" => "Fremdzugriff",
    # "Schluesselnummer" => "Schluesselnummer",
);

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
my %frameReadings = (
 'Temp-Aussen'              => { addr => 0x000, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Aussen-24h'          => { addr => 0x004, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Aussen-1h'           => { addr => 0x008, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Ruecklauf-Soll'      => { addr => 0x00C, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Ruecklauf'           => { addr => 0x010, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Vorlauf'             => { addr => 0x014, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Raum'                => { addr => 0x018, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Raum-1h'             => { addr => 0x01C, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Temp-WQuelle-Ein'         => { addr => 0x020, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Temp-WQuelle-Aus'         => { addr => 0x024, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Verdampfer'          => { addr => 0x028, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Kondensator'         => { addr => 0x02C, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Ww-Temp'                  => { addr => 0x030, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Zeit'                     => { addr => 0x034, bytes => 0x006, fmat=> '%4$02d.%5$02d.%6$02d %3$02d:%2$02d:%1$02d', unp => 'CCCCCC'},
 'Uhrzeit'                  => { addr => 0x034, bytes => 0x003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Datum'                    => { addr => 0x037, bytes => 0x003, fmat => '%02d.%02d.%02d', unp => 'CCC'},
 'Messbegin-Zeit'           => { addr => 0x03A, bytes => 0x003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Messbegin-Datum'          => { addr => 0x03D, bytes => 0x003, fmat => '%02d.%02d.%02d', unp => 'CCC' },
 'Hz-Messergebnis'          => { addr => 0x040, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Ww-Messergenis'           => { addr => 0x044, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Mess-Reset'               => { addr => 0x048, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 'KomprBeginn-Zeit'         => { addr => 0x049, bytes => 0x003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'KomprBeginn-Datum'        => { addr => 0x04C, bytes => 0x003, fmat => '%02d.%02d.%02d', unp => 'CCC' },
 'KomprBetrStunden'         => { addr => 0x04F, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Kompr-Mess-Reset'         => { addr => 0x053, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 'Unterbrechungen'          => { addr => 0x054, bytes => 0x001, unp => 'B8' },
 'Warnung-Eingang'          => { addr => 0x055, bytes => 0x001, unp => 'B8' },
 'Warnung-Ausgang'          => { addr => 0x056, bytes => 0x001, unp => 'B8' },
 'Warnung-Sonstige'         => { addr => 0x057, bytes => 0x001, unp => 'B8' },
 'Ausfaelle'                => { addr => 0x058, bytes => 0x001, unp => 'B8' },
 'Fuehler-Ausfall'          => { addr => 0x059, bytes => 0x001, unp => 'B8' },
 'Fuehler-KurzSchl'         => { addr => 0x05A, bytes => 0x001, unp => 'B8' },
 'FuehlRaum-KurzSchl'       => { addr => 0x05E, bytes => 0x001, unp => 'B8' },
 'FuehlRaum-Ausfall'        => { addr => 0x05D, bytes => 0x001, unp => 'B8' },
 'FuehlRaum-Zaehler0'       => { addr => 0x05F, bytes => 0x002, unp => 'n' },
 'FuehlerZaehler0'          => { addr => 0x05B, bytes => 0x002, unp => 'n' },
 'Ausfall-Zeit'             => { addr => 0x061, bytes => 0x003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Ausfall-Datum'            => { addr => 0x064, bytes => 0x003, fmat => '%02d.%02d.%02d', unp => 'CCC' },
 'Ausfall-BetriebMode'      => { addr => 0x067, bytes => 0x001, unp => 'B8' },
 'Ausfall-Do-Buffer'        => { addr => 0x068, bytes => 0x001, unp => 'B8' },
 'Ausfall-Di-Buffer'        => { addr => 0x069, bytes => 0x001, unp => 'B8' },
 'Ausfall-FuehlAusfall'     => { addr => 0x06A, bytes => 0x001, unp => 'B8' },
 'Ausfall-FuehlKurzsch'     => { addr => 0x06B, bytes => 0x001, unp => 'B8' },
 'Ausfall-Temp-Aussen'      => { addr => 0x06C, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-WQu-Ein'     => { addr => 0x070, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-WQu-Aus'     => { addr => 0x074, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-Verdampfer'  => { addr => 0x078, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-Ruecklf'     => { addr => 0x07C, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-Vorlauf'     => { addr => 0x080, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-Kondensator' => { addr => 0x084, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Temp-WWasser'     => { addr => 0x088, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Ausfall-RaumAusfall'      => { addr => 0x08C, bytes => 0x001, unp => 'B8' },
 'Ausfall-RaumKurzsch'      => { addr => 0x08D, bytes => 0x001, unp => 'B8' },
 'Ausfall-Temp-Raum'        => { addr => 0x08E, bytes => 0x004, fmat => '%0.1f', unp => 'f<' },
 'Ausfall-Reset'            => { addr => 0x092, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 'Kennwort'                 => { addr => 0x093, bytes => 0x001, unp => 'C', min => 0, max => 255 },
 'Betriebszustaende'        => { addr => 0x096, bytes => 0x001, unp => 'B8' },
 'Do-Buffer'                => { addr => 0x097, bytes => 0x001, unp => 'B8' },
 'Di-Buffer'                => { addr => 0x098, bytes => 0x001, unp => 'B8' },
 'Status-Gesamt'            => { addr => 0x099, bytes => 0x002, unp => 'n' },
 'Status-Verriegel'         => { addr => 0x09B, bytes => 0x002, unp => 'n' },
 'Status-Heizung'           => { addr => 0x09D, bytes => 0x002, unp => 'n' },
 'Status-Stufe2'            => { addr => 0x09F, bytes => 0x002, unp => 'n' },
 'Status-Wasser'            => { addr => 0x0A1, bytes => 0x002, unp => 'n' },
 'Status-WPumpe'            => { addr => 0x0A3, bytes => 0x002, unp => 'n' },
 'Mode-Heizung'             => { addr => 0x0A5, bytes => 0x001, unp => 'B8' },
 'Mode-Wasser'              => { addr => 0x0A6, bytes => 0x001, unp => 'B8' },
 'Hz'                       => { addr => 0x0A5, bytes => 0x001, unp => 'b' },
 'Ww'                       => { addr => 0x0A6, bytes => 0x001, unp => 'b' },
 'Versions-Datum'           => { addr => 0x0A7, bytes => 0x003, fmat => '%02d.%02d.%02d', unp => 'CCC' },
 'CPU-Boot-Zeit'            => { addr => 0x0AA, bytes => 0x003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'CPU-Boot-Datum'           => { addr => 0x0AD, bytes => 0x003, fmat => '%02d.%02d.%02d', unp => 'CCC' },
 'CRC-Summe'                => { addr => 0x0B0, bytes => 0x002, unp => 'n' },
 'Hz-Abschaltung'           => { addr => 0x0B3, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 'Hz-Temp-Einsatz'          => { addr => 0x0B4, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 10.0, max => 30.0},
 'Hz-Temp-BasisSoll'        => { addr => 0x0B8, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 15.0, max => 50.0 },
 'Hz-KlSteilheit'           => { addr => 0x0BC, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 0.0, max => 100.0 },
 'Hz-SchnellAufhz'          => { addr => 0x0C0, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 'Hz-Zeit-Ein'              => { addr => 0x0C1, bytes => 0x003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Hz-Zeit-Aus'              => { addr => 0x0C4, bytes => 0x003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Hz-Anhebung-Ein'          => { addr => 0x0C7, bytes => 0x003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Hz-Anhebung-Aus'          => { addr => 0x0CA, bytes => 0x003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Hz-Temp-RaumSoll'         => { addr => 0x0CD, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 15.0, max => 30.0 },
 'Hz-Raum-Einfluss'         => { addr => 0x0D1, bytes => 0x001, unp => 'C', min => 0, max => 200 },
 'Hz-Ext-Anhebung'          => { addr => 0x0D2, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => -5.0, max => 5.0 },
 'Hz-Begrenzung'            => { addr => 0x0D6, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 10.0, max => 50.0 },
 'Hz-Stufe2-Begrenzung'     => { addr => 0x0DA, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 10.0, max => 60.0 },
 'Hz-Hysterese'             => { addr => 0x0DE, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 1.0, max => 3.0 },
 'Hz-PumpenNachl'           => { addr => 0x0E2, bytes => 0x001, unp => 'C', min => 0, max => 20 },
 'Ww-Abschaltung'           => { addr => 0x0E3, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 'Ww-Zeit-Ein'              => { addr => 0x0E4, bytes => 0x003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Ww-Zeit-Aus'              => { addr => 0x0E7, bytes => 0x003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Ww-Temp-Soll'             => { addr => 0x0EA, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 20.0, max => 55.0 },
 'Ww-Becken-Temp-Soll'      => { addr => 0x0EE, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 20.0, max => 35.0 },
 'Ww-Hysterese'             => { addr => 0x0F2, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 5.0, max => 10.0 },
 'Ww-Becken-Hysterese'      => { addr => 0x0F6, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 0.5, max => 5.0 },
 'Unterdr-Warnung-Eingang'     => { addr => 0x0FA, bytes => 0x001, unp => 'B8' },
 'Unterdr-Warnung-Ausgang'     => { addr => 0x0FB, bytes => 0x001, unp => 'B8' },
 'Unterdr-Warnung-Sonstige'    => { addr => 0x0FC, bytes => 0x001, unp => 'B8' },
 'Betriebs-Mode'            => { addr => 0x0FD, bytes => 0x003, fmat => '%d.%d.%d', unp => 'CCC' },
 'Modem-Klingelzeichen'        => { addr => 0x100, bytes => 0x001, unp => 'C', min => 1, max => 6 },
 'Fremdzugriff'             => { addr => 0x101, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 'Schluesselnummer'         => { addr => 0x102, bytes => 0x001, unp => 'C', min => 0, max => 255 },
 # ---- Might not be correct (1)
 'Hz-Ext-Freigabe'          => { addr => 0x103, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 'Hz-Ext-TempRueckl-Soll'   => { addr => 0x104, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => 20.0, max => 30.0 },
 # ---- End of (1)
 'Temp-QAus-Min'            => { addr => 0x108, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => -25.0, max => 20.0 },
 'Temp-Verdampfer-Min'      => { addr => 0x10C, bytes => 0x004, fmat => '%0.1f', unp => 'f<', min => -25.0, max => 20.0 },
 # ---- Might not be correct (2)
 'Estrich-Aufhz'            => { addr => 0x110, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 'Hz-ExtSteuerung'          => { addr => 0x111, bytes => 0x001, unp => 'B8' },
 'St2-bei-EvuAbsch'         => { addr => 0x112, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 'Freigabe-Beckenwasser'    => { addr => 0x113, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 # ---- End of (2)
 'Do-Handkanal'             => { addr => 0x114, bytes => 0x001, unp => 'C', min => 0, max => 8 },
 'Do-Handkanal-Ein'         => { addr => 0x115, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 'AnalogKorrFaktor'         => { addr => 0x116, bytes => 0x004, fmat => '%0.4f', unp => 'f<', min => 0.8000, max => 1.2000 },
 # Disabled because unsure if readings are correct:
 # 'Neu-Start'               => { addr => 0x120, bytes => 0x001, unp => 'C', min => 0, max => 1 },
 # 'Run-Flag'                => { addr => 0x121, bytes => 0x001, unp => 'C', min => 0, max => 1 },
);

#
# FHEM module intitialisation
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
    $hash->{AttrList} =
      "do_not_notify:1,0 " . $readingFnAttributes;
}

#
# Define command
# init internal values, open device,
# set internal timer to send read command / wakeup
#########################################################################                                   #
sub WKRCD4_Define($$)
{
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return "wrong syntax: define <name> WKRCD4 [devicename\@speed|none] [interval]"
      if ( @a < 3 );

    DevIo_CloseDev($hash);
    my $name = $a[0];
    my $dev  = $a[2];
    my $interval  = 60;

    if ( $dev eq "none" ) {
        Log3 undef, 1, "$name: device is none, commands will be echoed only";
        return undef;
    }

    if(int(@a) == 4) {
        $interval= $a[3];
        if ($interval < 20) {
            return "interval too small, please use something > 20, default is 60";
        }
    }

    $hash->{buffer}             = "";

    $hash->{DeviceName}         = $dev;
    $hash->{INTERVAL}           = $interval;

    $hash->{SerialRequests}     = 0;
    $hash->{SerialGoodReads}    = 0;
    $hash->{SerialBadReads}     = 0;

    # send wakeup string (read 2 values preceeded with AT)
    $hash->{LastRequestAdr}     = 0;
    $hash->{LastRequestLen}     = 4;
    $hash->{LastRequest}        = gettimeofday();
    my $ret = DevIo_OpenDev( $hash, 0, "WKRCD4_Wakeup" );

    # initial read after 3 secs, there timer is set to interval for update and wakeup
    InternalTimer(gettimeofday()+3, "WKRCD4_GetUpdate", $hash, 0);

    return $ret;
}

#
# undefine command when device is deleted
#########################################################################
sub WKRCD4_Undef($$)
{
    my ( $hash, $arg ) = @_;
    DevIo_CloseDev($hash);
    RemoveInternalTimer($hash);
    return undef;
}


#
# Encode the data to be sent to the device (0x10 gets doubled)
#########################################################################
sub Encode10 (@) {
    my @a = ();
    for my $byte (@_) {
        push @a, $byte;
        push @a, $byte if $byte == 0x10;
    }
    return @a;
}

#
# create a command for the WP as byte array
#########################################################################
sub WPCMD($$$$;@)
{
    my ($hash, $cmd, $addr, $len, @value ) = @_;
    my $name = $hash->{NAME};
    my @frame = ();

    if ($cmd eq "read") {
        @frame = (0x01, 0x15, Encode10($addr>>8, $addr%256), Encode10($len>>8, $len%256));
    } elsif ($cmd eq "write") {
        @frame = (0x01, 0x13, Encode10($addr>>8, $addr%256), Encode10(@value));
    } else {
        Log3 $name, 3, "$name: undefined cmd ($cmd) in WPCMD";
        return 0;
    }
    my $crc = CRC16(@frame);
    return (0xff, 0x10, 0x02, @frame, 0x10, 0x03, $crc >> 8, $crc % 256, 0xff);
}

#
# GET command
#########################################################################
sub WKRCD4_Get($@)
{
    my ( $hash, @a ) = @_;
    return "\"get WKRCD4\" needs at least an argument" if ( @a < 2 );

    my $name = shift @a;
    my $attr = shift @a;
    my $arg = join("", @a);

    if(!$WKRCD4_gets{$attr}) {
        my @cList = keys %WKRCD4_gets;
        return "Unknown argument $attr, choose one of " . join(" ", @cList);
    }

    # get Hash pointer for the attribute requested from the global hash
    my $properties = $frameReadings{$WKRCD4_gets{$attr}};
    if(!$properties) {
        return "No Entry in frameReadings found for $attr";
    }

    # get details about the attribute requested from its hash
    my $addr  = $properties->{addr};
    my $bytes = $properties->{bytes};
    Log3 $name, 4, sprintf ("$name: Get will read %02x bytes starting from %02x for $attr", $bytes, $addr);

    # create command for WP
    my $cmd = pack('C*', WPCMD($hash, 'read', $addr, $bytes));

    # set internal variables to track what is happending
    $hash->{LastRequestAdr} = $addr;
    $hash->{LastRequestLen} = $bytes;
    $hash->{LastRequest}    = gettimeofday();
    $hash->{SerialRequests}++;

    Log3 $name, 4, "$name: Get -> Call DevIo_SimpleWrite: " . unpack ('H*', $cmd);
    DevIo_SimpleWrite( $hash, $cmd , 0 );

    return sprintf ("Read %02x bytes starting from %02x", $bytes, $addr);
}

#
# SET command
#########################################################################
sub WKRCD4_Set($@)
{
    my ( $hash, @a ) = @_;
    return "\"set WKRCD4\" needs at least an argument" if ( @a < 2 );

    my $name = shift @a;
    my $attr = shift @a;
    my $arg = join("", @a);

    if(!defined($WKRCD4_sets{$attr})) {
        my @cList = keys %WKRCD4_sets;
        return "Unknown argument $attr, choose one of " . join(" ", @cList);
    }

    # get Hash pointer for the attribute requested from the global hash
    my $properties = $frameReadings{$WKRCD4_sets{$attr}};
    if(!$properties) {
        return "No Entry in frameReadings found for $attr";
    }

    # get details about the attribute requested from its hash
    my $addr  = $properties->{addr};
    my $bytes = $properties->{bytes};
    my $min   = $properties->{min};
    my $max   = $properties->{max};
    my $unp   = $properties->{unp};

    return "a numerical value between $min and $max is expected, got $arg instead"
        if($arg !~ m/^[\d.]+$/ || $arg < $min || $arg > $max);

    # convert string to value needed for command
    my $vp    = pack($unp, $arg);
    my @value = unpack ('C*', $vp);

    Log3 $name, 4, sprintf ("$name: Set will write $attr: %02x bytes starting from %02x with %s (%s) packed with $unp", $bytes, $addr, unpack ('H*', $vp), unpack ($unp, $vp));
    my $cmd = pack('C*', WPCMD($hash, 'write', $addr, $bytes, @value));

    # set internal variables to track what is happending
    $hash->{LastRequestAdr} = $addr;
    $hash->{LastRequestLen} = $bytes;
    $hash->{LastRequest}    = gettimeofday();
    $hash->{SerialRequests}++;
    Log3 $name, 4, "Set -> Call DevIo_SimpleWrite: " . unpack ('H*', $cmd);
    DevIo_SimpleWrite( $hash, $cmd , 0 );

    return sprintf ("Wrote %02x bytes starting from %02x with %s (%s)", $bytes, $addr, unpack ('H*', $vp), unpack ($unp, $vp));
}



#########################################################################
# called from the global loop, when the select for hash->{FD} reports data
sub WKRCD4_Read($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # read from serial device
    my $buf = DevIo_SimpleRead($hash);
    return "" if ( !defined($buf) );

    $hash->{buffer} .= $buf;
    Log3 $name, 5, "$name: read buffer content: " . unpack ('H*', $hash->{buffer});

    # did we already get a full frame?
    if ( $hash->{buffer} !~ /\x16\x10\x02(.{2})(.*)\x10\x03(.{2})(.*)/s )
    {
        Log3 $name, 5, "$name: read NoMatch: " . unpack ('H*', $hash->{buffer});
        return "";
    }
    my $msg    = unpack ('H*', $1);
    my @aframe = unpack ('C*', $1 . $2);
    my $crc    = unpack ('S>', $3);
    my $rest   = $4;

    $hash->{buffer} = $rest;
    Log3 $name, 4, "$name: read match msg: $msg CRC $crc";
    Log3 $name, 5, "$name: read frame is " . unpack ('H*', pack ('C*', @aframe)) . ", Rest " . unpack ('H*', $rest);

    # calculate CRC and compare with CRC from read
    my $crc2 = CRC16(@aframe);
    if ($crc != $crc2) {
        Log3 $name, 3, "$name: read Bad CRC from WP: $crc, berechnet: $crc2";
        Log3 $name, 4, "$name: read Frame was " . unpack ('H*', pack ('C*', @aframe));
        $hash->{SerialBadReads} ++;
        @aframe = ();
        return "";
    };
    Log3 $name, 4, "$name: read CRC Ok.";
    $hash->{SerialGoodReads}++;

    # reply to read request ?
    if ($msg eq "0017") {
        my @data;
        for(my $i=0,my $offset=2;$offset<=$#aframe;$offset++,$i++)
        {
            # remove duplicate 0x10 (frames are encoded like this)
            if (($aframe[$offset]==16)&&($aframe[$offset+1]==16)) { $offset++; }
            $data[$i] = $aframe[$offset];
        }
        Log3 $name, 4, "$name: read -> Parse with relative request start " . $hash->{LastRequestAdr} . " Len " . $hash->{LastRequestLen};
        # extract values from data
        parseReadings($hash, @data);
    } elsif ($msg eq "0011") {
        # reply to write
    } else {
        Log3 $name, 3, "$name: read got unknown Msg type " . $msg . " in " . $hash->{buffer};
    }
    @aframe = ();
    return "";
}

#
# copied from other FHEM modules
#########################################################################
sub WKRCD4_Ready($)
{
    my ($hash) = @_;

    return DevIo_OpenDev( $hash, 1, undef )
      if ( $hash->{STATE} eq "disconnected" );

    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;
    return ( $InBytes > 0 );
}

#
# send wakeup /at least my waterkotte WP doesn't respond otherwise
#########################################################################
sub WKRCD4_Wakeup($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    $hash->{SerialRequests}++;

    $hash->{LastRequestAdr} = 0;
    $hash->{LastRequestLen} = 4;
    $hash->{LastRequest}    = gettimeofday();

    my $cmd = "41540D10020115000000041003FE0310020115003000041003FDC3100201150034000410037D90";
    DevIo_SimpleWrite( $hash, $cmd , 1 );

    Log3 $name, 5, "$name: sent wakeup string: " . $cmd . " done.";
    return undef;
}

#
# request new data from WP
###################################
sub WKRCD4_GetUpdate($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "WKRCD4_GetUpdate", $hash, 1);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}/2, "WKRCD4_Wakeup", $hash, 1);

    $hash->{SerialRequests}++;

    my $cmd = pack('C*', WPCMD($hash, 'read', 0, 0x0122));
    $hash->{LastRequestAdr} = 0;
    $hash->{LastRequestLen} = 0x0122;
    $hash->{LastRequest}    = gettimeofday();
    DevIo_SimpleWrite( $hash, $cmd , 0 );

    Log3 $name, 5, "$name: GetUpdate -> Call DevIo_SimpleWrite: " . unpack ('H*', $cmd);

    return 1;
}

#
# calculate CRC16 for communication with the WP
#####################################################################################################
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
# get Values out of data read
#####################################################################################################
sub parseReadings
{
    my ($hash, @data) = @_;
    my $name = $hash->{NAME};

    my $reqStart = $hash->{LastRequestAdr};
    my $reqLen   = $hash->{LastRequestLen};

    # get enough bytes?
    if (@data >= $reqLen)
    {
        readingsBeginUpdate($hash);
        # go through all possible readings from global hash
        while (my ($reading, $property) = each(%frameReadings))
        {
            my $addr  = $property->{addr};
            my $bytes = $property->{bytes};

            # is reading inside data we got?
            if (($addr >= $reqStart) &&
                ($addr + $bytes <= $reqStart + $reqLen))
            {
                my $Idx = $addr - $reqStart;
                # get relevant slice from data array
                my @slice = @data[$Idx .. $Idx + $bytes - 1];

                # convert according to rules in global hash or defaults
                my $pack   = ($property->{pack}) ? $property->{pack} : 'C*';
                my $unpack = ($property->{unp})  ? $property->{unp}  : 'H*';
                my $fmat   = ($property->{fmat}) ? $property->{fmat} : '%s';
                #my $value = sprintf ($fmat, unpack ($unpack, pack ($pack, @slice))) . " packed with $pack, unpacked with $unpack, (hex " . unpack ('H*', pack ('C*', @slice)) . ") format $fmat";
                my $value = sprintf ($fmat, unpack ($unpack, pack ($pack, @slice)));

                readingsBulkUpdate( $hash, $reading, $value );
                Log3 $name, 4, "$name: parse set reading $reading to $value" if (@data <= 20);
            }
        }
        # ----- Part disabled because it can be read via notify/manually too -----
        # my $Status = "Leerlauf";
        # if (ReadingsVal($name, "Hz", 0)) {
        #     $Status = sprintf ("Heizung %s", ReadingsVal ($name, "Temp-Vorlauf", 0));
        # } elsif (ReadingsVal($name, "Ww", 0)) {
        #     $Status = sprintf ("Warmwasser %s", ReadingsVal ($name, "Ww-Temp", 0));
        # }
        # $Status = encode ("utf8", $Status);
        # readingsBulkUpdate( $hash, "Status", $Status);
        # ----- Disabled part END -----
        readingsEndUpdate( $hash, 1 );
    }
    else
    {
        Log3 $name, 3, "$name: parse - data len smaller than requested ($reqLen) : " . unpack ('H*', pack ('C*', @data));
        return 0;
    }
}

1;

# FHEM module for the Waterkotte Resümat CD4 control unit

## General information
### Disclaimer
Do **not set any values** if the corresponding readings don't match the displayed data on the control unit itself or if any other readings are not correct! I'm not responsible for any damage!

### About the module
**This module will not work for your heat pump if the official one (by user [StefanStrobel](https://wiki.fhem.de/wiki/Benutzer:StefanStrobel)) works for you! - It uses different memory addresses!** Successfully tested with a Resümat CD4 with software version 8011 on a _DS 5009.3_ heat pump.

If it does not work for you, try to use the official module as seen in the [FHEM wiki](https://wiki.fhem.de/wiki/Waterkotte_heat_pump_with_Res%C3%BCmat_CD4).  
It should already be in the `contrib/` folder of your FHEM installation.

Can be used to request/change settings from older Waterkotte heat pumps with the Resümat CD4 control unit via the RS232 port.  
Based on [98_WKRCD4.pm](https://svn.fhem.de/fhem/trunk/fhem/contrib/98_WKRCD4.pm).

## Usage
Just copy `98_WKRCD4.pm` into the FHEM/ folder of your FHEM installation.  
Here's an example of the full path: `/opt/fhem/FHEM/98_WKRCD4.pm`

After that, make sure to enable the module by restarting FHEM with `shutdown restart`.

### Defining it
`define <Name> WKRCD4 <Device>@<Speed> <Read-Interval>`  

You can use a USB-to-RS232-converter and plug it into your FHEM server. Most of these devices use `/dev/ttyUSB0` as the device path but if you're unsure, just check the syslog with `cat /var/log/syslog | grep tty` after plugging it in.

The default speed/baud rate is `9600`. The default read interval is `60` (poll every minute).

By the way, if your heat pump is too far away from your server:  
Just use another Raspberry Pi and use _ser2net_ to transfer the serial data over the network. More information about that is available at the end of the document.

Example command:  
`define Heating WKRCD4 /dev/ttyUSB0@9600 60`  

### Enabling advanced mode
Most sets/gets are hidden by default because they usually don't have to be changed that often.
You can enable them by setting the attribute `enableAdvancedMode` to `1`.  

`attr <name> enableAdvancedMode 1`

To disable the adv. mode, just delete the attribute or set it to `0`.

## Protocol analysis
By sending hexadecimal strings (**without the spaces**) to the serial interface of the control unit you can receive a response with some hexadecimal data.  

Please note: If the control unit doesn't respond, try sending "AT" and a carriage return:  
`41 54 0D`
 
---

Example command to **read data**:  
`10 02 01 15 0000 0002 10 03 FE17`

### Further explanation (CMD to read data)
`10` - DLE (Data Link Escape)  
`02` - STX (Start of Text)  
`01 15` - CMD (Heat pump command, 01 15 means "Read memory")  
`0000` - Start address  
`0002` - Bytes to read after start address (if you start at 0x00, the max value is 0x152 with SW-Version 8011)  
`10` - DLE (Data Link Escape)  
`03` - ETX (End of Text)  
`FE17` - CRC-16 checksum of CMD, start address and bytes to read (More information below)

---

Example command to **write data**:  
`10 02 01 13 00BC 0000C841 10 03 851C`

### Further explanation (CMD to write data)
`10 02` - DLE / STX  
`01 13` - CMD (Heat pump command, 01 13 means "Write memory")  
`00BC` - Start address  
`0000C841` - Bytes to write after start address (0000C841 is a float - 25.0)  
`10 03` - DLE / ETX  
`851C` - CRC-16 checksum of CMD, start address and bytes to write (More information below)

---

Example command to **sync the time/date**:  
`10 02 01 14 0000 1B 1E 0C 16 02 13 1003 AF8D`

### Further explanation (CMD to sync time/date)
`10 02` - DLE / STX  
`01 14` - CMD (Heat pump command, 01 14 means "Write time/date memory")  
`0000` - Start address (?)  
`1B 1E 0C` - SS:MM:HH (In that case: 27:30:12)  
`16 02 13` - DD.MM.YY (In that case: 22.02.19)  
`10 03` - DLE / ETX  
`AF8D` - CRC-16 checksum of CMD, start address and time/date (More information below)

---

### Available CMDs
`01 15` - Read memory  
`01 14` - Write time/date memory (Maybe more, won't try that...)  
`01 13` - Write memory (**Don't destroy your heat pump!**)

---

### Response
#### Read response

Response for command `10 02 01 15 00E9 0001 10 03 732A` as an example:  
`16 10 02 00 17 00 10 03 7200 16`  

The bytes between `17` and `10` are the received data bytes.  
In that case, it would be `00`, because address `00E9` is the field "Ww-Abschaltung" (German for 'Warm water disabled'). At the time of the request, warm water was enabled, so the answer is `0`, not `1`.  
`7200` is the checksum once again.

Please note: If `10` appears to times in a row in the received data bytes you have to skip the second `10` to get correct values.

---

#### Write response
The control unit acknowledges any write command with the following response:  
`16 10 02 00 11 00 10 03 6600 16`

### Calculating a CRC-16
Some people at the IP-Symcom forums already created [two PHP scripts to calculate the CRC-16](https://www.symcon.de/forum/threads/2092-ComPort-und-Waterkotte-abfragen/page2).  
Alternatively, you can look on the web for scripts/pages that can calculate a `CRC16_BUYPASS` or a custom CRC-16. Here are the parameters:  

CRC-Order: `16`  
Input type: `Hex`  
Polynomial: `0x8005`  
Initial value: `0x0`  
LSB/Final Xor Value: `0x0`  
Input/data reflected/reversed: `No`  
Result reflected/reversed: `No`  

For me, [crccalc.com](https://crccalc.com/?crc=01%2015%200000%200002&method=crc16&datatype=hex) worked well. Just enter the part of the command between `10 02` and `10 03` - that would be the CMD, the start address and the bytes to be read after the start address. Make sure to choose CRC-16, the correct result is `CRC-16/BUYPASS`. 

### Data types
  * Floats -----> Reversed IEEE float notation (4 byte)
  * Integers ---> 1 or 2 bytes (8 or 16 bits)
  * Binary -----> 1 byte
  * Date -------> 3 bytes (DD MM YY)
  * Time -------> 3 bytes (SS MM HH)

### Links
If you need more information about the protocol, visit [https://www.symcon.de/forum/threads/2092-ComPort-und-Waterkotte-abfragen](https://www.symcon.de/forum/threads/2092-ComPort-und-Waterkotte-abfragen) (German).

## Using ser2net for serial communication over the network
Install ser2net by opening a terminal/SSH session:  
`sudo apt-get install ser2net -y`

After that, edit `/etc/ser2net.conf` with your favorite text editor.  
`sudo nano /etc/ser2net.conf`

Go to the end of the file (Ctrl+W, Ctrl+V in nano) and make sure to comment out the BANNER line and the 4 default entries (2000:telnet, 2001:telnet, 3000:telnet, 3001:telnet) by prepending a `#` to each line.

At the end of the file, add the following line:  
`2000:raw:0:/dev/ttyUSB0:9600 NONE 1STOPBIT 8DATABITS`

`2000` is the used port, `raw` is the mode, `/dev/ttyUSB0` the device (change it if you have to) and `9600` is the speed/baud rate.

Save the file and close the text editor. The last step: Restart ser2net.  
`sudo /etc/init.d/ser2net restart`

### Defining the ser2net-port in FHEM
`define Heating WKRCD4 192.168.1.23:2000@9600 60`  
It's basically like a normal define, just change the device to `IP:PORT`. (The port is 2000 in our case!)

## Examples
Check out [examples.md](/examples.md) to find some snippets for attributes and notifies.

## Screenshots
### SVG plot: Outside temperature
![Plot: Outside temp](/img/scr_svg-plot_aussentemp.png "Plot: Outside temp")

### SVG plot: Flow/return flow
![Plot: Flow/return](/img/scr_svg-plot_vor-ruecklauf.png "Plot: Flow/return")

### ReadingsGroup: Status information
![ReadingsGroup](/img/scr_readingsgroup_heizung.png "ReadingsGroup")

## List of get/set values
  * Hz-KlSteilheit
  * Hz-Temp-BasisSoll
  * Hz-Temp-Einsatz
  * Hz-Temp-RaumSoll
  * Ww-Temp-Soll
  * Hz-Abschaltung
  * Ww-Abschaltung
  * menuEntry (menu entry of a reading on the control unit, get only)
  * menuEntryHidden (1 if hidden by default, 0 if not, get only)
  * dateTimeSync (set only)
  * ... more available but disabled by default. (`attr <name> enableAdvancedMode 1`) - **Be careful!**

## List of readings
  * AnalogKorrFaktor
  * Ausfaelle
  * Ausfall-BetriebMode
  * Ausfall-Datum
  * Ausfall-Di-Buffer
  * Ausfall-Do-Buffer
  * Ausfall-FuehlAusfall
  * Ausfall-FuehlKurzsch
  * Ausfall-RaumAusfall
  * Ausfall-RaumKurzsch
  * Ausfall-Reset
  * Ausfall-Temp-Aussen
  * Ausfall-Temp-Kondensator
  * Ausfall-Temp-Raum
  * Ausfall-Temp-Ruecklf
  * Ausfall-Temp-Verdampfer
  * Ausfall-Temp-Vorlauf
  * Ausfall-Temp-WQu-Aus
  * Ausfall-Temp-WQu-Ein
  * Ausfall-Temp-WWasser
  * Ausfall-Zeit
  * Betriebs-Mode
  * Betriebszustaende
  * CPU-Boot-Datum
  * CPU-Boot-Zeit
  * CRC-Summe
  * Datum
  * Di-Buffer
  * Do-Buffer
  * Do-Handkanal
  * Do-Handkanal-Ein
  * Estrich-Aufhz
  * Freigabe-Beckenwasser
  * Fremdzugriff
  * FuehlRaum-Ausfall
  * FuehlRaum-KurzSchl
  * FuehlRaum-Zaehler0
  * Fuehler-Ausfall
  * Fuehler-KurzSchl
  * FuehlerZaehler0
  * Hz
  * Hz-Abschaltung
  * Hz-Anhebung-Aus
  * Hz-Anhebung-Ein
  * Hz-Begrenzung
  * Hz-Ext-Anhebung
  * Hz-Ext-Freigabe
  * Hz-Ext-TempRueckl-Soll
  * Hz-ExtSteuerung
  * Hz-Hysterese
  * Hz-KlSteilheit
  * Hz-Messergebnis
  * Hz-PumpenNachl
  * Hz-Raum-Einfluss
  * Hz-SchnellAufhz
  * Hz-Stufe2-Begrenzung
  * Hz-Temp-BasisSoll
  * Hz-Temp-Einsatz
  * Hz-Temp-RaumSoll
  * Hz-Zeit-Aus
  * Hz-Zeit-Ein
  * Kennwort
  * Kompr-Mess-Reset
  * KomprBeginn-Datum
  * KomprBeginn-Zeit
  * KomprBetrStunden
  * Mess-Reset
  * Messbegin-Datum
  * Messbegin-Zeit
  * Mode-Heizung
  * Mode-Wasser
  * Modem-Klingelzeit
  * Schluesselnummer
  * St2-bei-EvuAbsch
  * Status-Gesamt
  * Status-Heizung
  * Status-Stufe2
  * Status-Verriegel
  * Status-WPumpe
  * Status-Wasser
  * Temp-Aussen
  * Temp-Aussen-1h
  * Temp-Aussen-24h
  * Temp-Kondensator
  * Temp-QAus-Min
  * Temp-Raum
  * Temp-Raum-1h
  * Temp-Ruecklauf
  * Temp-Ruecklauf-Soll
  * Temp-Verdampfer
  * Temp-Verdampfer-Min
  * Temp-Vorlauf
  * Temp-WQuelle-Aus
  * Temp-WQuelle-Ein
  * Uhrzeit
  * Unterbrechungen
  * Unterdr-Warnung-Ausgang
  * Unterdr-Warnung-Eingang
  * Unterdr-Warnung-Sonstige
  * Versions-Datum
  * Warnung-Ausgang
  * Warnung-Eingang
  * Warnung-Sonstige
  * Ww
  * Ww-Abschaltung
  * Ww-Becken-Hysterese
  * Ww-Becken-Temp-Soll
  * Ww-Hysterese
  * Ww-Messergenis
  * Ww-Temp
  * Ww-Temp-Soll
  * Ww-Zeit-Aus
  * Ww-Zeit-Ein
  * Zeit

# FHEM module for the Waterkotte Resümat CD4 control unit

**This module will not work for your heat pump if the official one (by user [StefanStrobel](https://wiki.fhem.de/wiki/Benutzer:StefanStrobel)) works for you!** Successfully tested with a Resümat CD4 with software version 8011 on a _DS 5009.3_ heat pump.

Can be used to request/change settings from older Waterkotte heat pumps with the Resümat CD4 control unit via the RS232 port.

Based on [98_WKRCD4.pm](https://svn.fhem.de/fhem/trunk/fhem/contrib/98_WKRCD4.pm). Take a look at the [FHEM wiki](https://wiki.fhem.de/wiki/Waterkotte_heat_pump_with_Res%C3%BCmat_CD4) for more information.



**Attention: The module does _not_ work on all Resümat CD4 control units. Tested on software version 8011. If it does not work for you,  try to use the official module as seen in the [FHEM wiki](https://wiki.fhem.de/wiki/Waterkotte_heat_pump_with_Res%C3%BCmat_CD4): It uses different memory addresses.**  
The official one should already be in the `contrib/` folder of your FHEM installation.

## Usage
Just copy `98_WKRCD4.pm` into the FHEM/ folder of your FHEM installation.  
Here's an example of the full path: `/opt/fhem/FHEM/98_WKRCD4.pm`

After that, make sure to enable the module by restarting FHEM with `shutdown restart`.

### Defining it
`define <Name> WKRCD4 <Device>@<Speed> <Read-Interval>`  

You can use a USB-to-RS232-converter and plug it into your FHEM server. Most of these devices use `/dev/ttyUSB0` as the device path but if you're unsure, just check the syslog with `cat /var/log/syslog` after plugging it in.

The default speed/baud rate is `9600`. The default read interval is `60` (poll every minute).

By the way, if your heat pump is too far away from your server:  
Just use another Raspberry Pi and use _ser2net_ to transfer the serial data over the network. More information about that is available at the end of the document.

Example command:  
`define Heating WKRCD4 /dev/ttyUSB0@9600 60`  

## Protocol analysis
By sending hexadecimal strings (without the spaces) to the serial interface of the control unit you can receive a response with some hexadecimal data.  

Example command:  
`10 02 01 15 0000 0002 10 03 FE17`

### Further explanation
`10` - DLE (Data Link Escape)  
`02` - STX (Start of Text)  
`01 15` - CMD (Heat pump command, 01 15 means "Read memory")  
`0000` - Start address  
`0002` - Bytes to read after start address (if you start at 0x00, the max value is 0x152 with SW-Version 8011)  
`10` - DLE (Data Link Escape)  
`03` - ETX (End of Text)  
`FE17` - CRC-16 checksum of CMD, start address and bytes to read (More information below)

### Available CMDs
`01 15` - Read memory  
`01 13` - Write memory (Check the code of the module for more information, the command is different compared to the read command! **Don't destroy your heat pump!**)

### Response
Response for command `10 02 01 15 00E3 0001 10 03 73A2` as an example:

`16 10 02 00 17 00 10 03 7200`  

The bytes between `17` and `10` are the received data bytes.  
In that case, it would be `00`, because address `00E3` is the field "Ww-Abschaltung" (German for 'Warm water disabled'). At the time of the request, warm water was enabled, so the answer is `0`, not `1`.  
`7200` is the checksum once again.

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
  * Floats -----> IEEE float notation (4 byte)
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
  * Ww-Becken-Temp-Soll
  * Ww-Hysterese
  * Ww-Becken-Hysterese
  * ... more available but disabled by default.

## List of readings
  * AnalogKorrFaktor
  * Ausfall-BetriebMode
  * Ausfall-Datum
  * Ausfall-Di-Buffer
  * Ausfall-Do-Buffer
  * Ausfall-FuehlAusfall
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
  * Betriebszustaende
  * CPU-Boot-Datum
  * CPU-Boot-Zeit
  * Datum
  * Di-Buffer
  * Do-Buffer
  * Fremdzugriff
  * FuehlerZaehler0
  * Hz
  * Hz-Abschaltung
  * Hz-Anhebung-Aus
  * Hz-Anhebung-Ein
  * Hz-Begrenzung
  * Hz-Ext-Anhebung
  * Hz-Ext-Freigabe
  * Hz-Hysterese
  * Hz-KlSteilheit
  * Hz-Messergebnis
  * Hz-PumpenNachl
  * Hz-Stufe2-Begrenzung
  * Hz-Temp-BasisSoll
  * Hz-Temp-Einsatz
  * Hz-Temp-RaumSoll
  * Hz-Zeit-Aus
  * Hz-Zeit-Ein
  * Kennwort
  * KomprBeginn-Datum
  * KomprBeginn-Zeit
  * KomprBetrStunden
  * Messbegin-Datum
  * Messbegin-Zeit
  * Mode-Heizung
  * Mode-Wasser
  * Modem-Klingelzeit
  * Schluesselnummer
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
  * Temp-Ruecklauf
  * Temp-Ruecklauf-Soll
  * Temp-Verdampfer
  * Temp-Verdampfer-Min
  * Temp-Vorlauf
  * Temp-WQuelle-Aus
  * Temp-WQuelle-Ein
  * Uhrzeit
  * Unterdr-Warn-Ausgang
  * Unterdr-Warn-Eingang
  * Unterdr-Warn-Sonstige
  * Versions-Datum
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

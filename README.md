# FHEM module for the Waterkotte Resümat CD4 control unit

Based on [98_WKRCD4.pm](https://svn.fhem.de/fhem/trunk/fhem/contrib/98_WKRCD4.pm) by user [StefanStrobel](https://wiki.fhem.de/wiki/Benutzer:StefanStrobel). Take a look at the [FHEM wiki](https://wiki.fhem.de/wiki/Waterkotte_heat_pump_with_Res%C3%BCmat_CD4) for more information.

Can be used to request/change settings from older Waterkotte heat pumps with the Resümat CD4 control unit via the RS232 port.

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
`0002` - Bytes to read after start address  
`10` - DLE (Data Link Escape)  
`03` - ETX (End of Text)  
`FE17` - CRC-16 checksum of CMD, start address and bytes to read (Poly 8005, Init 0, Lsb 0)

### Available CMDs
`01 15` - Read memory  
`01 13` - Write memory (Check the code of the module for more information, the command is different compared to the read command! **Don't destroy your heat pump!**)

### Response
Response for command `10 02 01 15 00E3 0001 10 03 73A2` as an example:

`16 10 02 00 17 00 10 03 7200`  

The bytes between `17` and `10` are the received data bytes.  
In that case, it would be `00`, because address `00e3` is the field "Ww-Abschaltung" (German for 'Warm water disabled'). At the time of the request, warm water was enabled, so the answer is `0`, not `1`.  
`7200` is the checksum once again.

### Links
If you need more information about the protocol, visit [https://www.symcon.de/forum/threads/2092-ComPort-und-Waterkotte-abfragen](https://www.symcon.de/forum/threads/2092-ComPort-und-Waterkotte-abfragen) (German).

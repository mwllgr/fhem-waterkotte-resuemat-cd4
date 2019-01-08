# FHEM module for the Waterkotte Resümat CD4 control unit

Based on [98_WKRCD4.pm](https://svn.fhem.de/fhem/trunk/fhem/contrib/98_WKRCD4.pm) by user [StefanStrobel](https://wiki.fhem.de/wiki/Benutzer:StefanStrobel). Take a look at the [FHEM wiki](https://wiki.fhem.de/wiki/Waterkotte_heat_pump_with_Res%C3%BCmat_CD4) for more information.

Can be used to request/change settings from older Waterkotte heat pumps with the Resümat CD4 control unit via the RS232 port.

## Usage
Just copy `98_WKRCD4.pm` into the FHEM/ folder of your FHEM installation.  
Here's an example of the full path: `/opt/fhem/FHEM/98_WKRCD4.pm`

After that, make sure to enable the module by restarting FHEM with `shutdown restart`.

### Defining it
`define <Name> WKRCD4 <Device@Speed> <Read-Interval>`  

You can use a USB-to-RS232-converter and plug it into your FHEM server. Most of these devices use `/dev/ttyUSB0` as the device path but if you're unsure, just check the syslog with `cat /var/log/syslog` after plugging it in.

By the way, if your heat pump is too far away from your server:  
Just use another Raspberry Pi and use _ser2net_ to transfer the serial data over the network. More information about that is available at the end of the document.

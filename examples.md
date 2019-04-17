# Example code snippets

## Attributes

### Only create event if a reading actually changed
Śet the attribute `event-on-change-reading` to `.*`:  
`attr DEVICENAME event-on-change-reading .*`

### State formatting for the heating device itself
Use the following code snippet for the attribute `stateFormat` to display some information instead of the regular "connected":
```
{
	my $state = "";
	my $hz = ReadingsVal($name, "Msg-Mode-Heizung", "---");
	my $dobuf = ReadingsVal($name, "Do-Buffer", "00000000");
	
	if($hz eq "KeinBedarf" || $hz eq "---")
	{
		# Pumpe-Hz / Pumpe-Hz, Kurbelwannenhz
		if($dobuf eq "00100000" || $dobuf eq "00101000")
		{
			$hz = "NurPumpe";
		}
	}
	
	$state = "Hz: " . $hz;
	$state .= " | Ww: " . ReadingsVal($name, "Msg-Mode-Wasser", "---");
	$state .= " | Aussen: " . ReadingsVal($name, "Temp-Aussen", "---");
}
```
After that, here's an example of what `state` looks like then: `Hz: Normal | Ww: KeinBedarf | Aussen: 5.0`

## Notifies
### Warnings
The following notify DEF code checks if there are any unsuppressed warnings.  
Make sure to change the *DEVICENAME* and to fill in some code.

```
DEVICENAME:Warnung.*:.* {
	if($EVTPART1 ne "00000000")
	{
		my $foundError = 0;
		
		my @evtSplit = split("", $EVTPART1);
		my @unterdrSplit = split("", ReadingsVal($NAME, "Unterdr-" . (split(":", $EVTPART0))[0], "11111111"));
		
		for(my $i = 0; $i < 8; $i++)
		{
			if($evtSplit[$i] == 1 && $unterdrSplit[$i] == 0)
			{
				$foundError = 1;
				last;
			}
		}
		
		if($foundError)
		{
			# Do something here...
		}
	}
}
```

### Failures
The following notify checks if there are any failures.  
Make sure to change the *DEVICENAME* and to fill in some code.

```
DEVICENAME:Ausfall-Zeit:.* {
	if(ReadingsVal($NAME, "Ausfall-Datum", "01.01.01") eq (sprintf("%02d.%02d", $mday, $month) . "." . substr($year, 2, 2)))
	{
		# Do something here...
	}
}
```

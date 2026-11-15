# IMove device ecosystem — feasibility decision

## Goal

Let the iPad control the iPhone 6s connected to the Mac mini while also managing its own location independently. A location change should affect the location the other person sees in Apple Find My.

## Path verified today

`IMove on iPad → Tailscale Serve → IMove on Mac mini → USB → iPhone 6s` works. This path changes the location the iPhone 6s shares in Find My. It does not change the iPad's own system location.

## Platform limit

A normally signed iOS/iPadOS app can read the device location with Core Location, but it cannot write a chosen coordinate as the device's system location. Xcode's location simulation is tied to development and testing. So a button added to the current IMove app on the iPad (A16, iPadOS 27) cannot change the iPad's Find My location without a Mac.

The **Use This iPad as My Location** option in Find My only switches the sharing source to the iPad; it does not fake the iPad's coordinates. When the 6s is the source, the 6s's current location is shared, and the iPad's own device location in Find My may keep showing its real location.

## A separate goal that might work without a Mac

For a jailbroken iPhone 6s (iOS 15.8.6), an authorized helper service running on the device, separate from IMove, could be explored. LocSim's command-line tool offers system-wide location simulation, and LocSim had already been tried on the 6s. For this path to work, each of the following must be verified on the device: the jailbreak stays active, LocSim's local command actually works, the remote connection is secure, the service keeps running, and Find My behaves as expected. If verified, the flow would be `IMove on iPad → private network → helper service on the 6s → LocSim`, and the Mac might not be needed to change the location. This is not an implemented or verified feature.

This path does not change the iPad's **own** location. There is no verified jailbreak or on-device way to write the system location on the current iPad (A16, iPadOS 27), so the app must not present that as a supported feature.

## App design

1. Model the target device, its connection type and its capabilities as separate records: a device managed over USB through the Mac; a jailbroken local node, if that is verified in the future; and a controlling device that can only read its real location.
2. Send location and route commands to the chosen target. Show clearly in the interface whether each target can change its Find My location.
3. Name "send the iPad's real location to the Mac/6s" as a different action from "change the iPad's own Find My location".
4. Only build the local service for the 6s after the LocSim command and secure private-network access have been verified on the device. Do not use an open internet port or an unauthenticated management endpoint.

## References

- Apple Core Location: https://developer.apple.com/documentation/corelocation/cllocationmanager
- Apple's Xcode location simulation: https://developer.apple.com/documentation/xcode/simulating-location-in-tests
- Apple's Find My sharing source setting: https://support.apple.com/guide/ipad/share-your-location-ipadb2310df7/27/ipados/27
- LocSim commands and compatibility notes: https://github.com/udevsharold/locsim
- Dopamine version support: https://github.com/opa334/Dopamine

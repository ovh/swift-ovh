![Swift Wrapper for OVH APIs](https://github.com/ovh/swift-ovh/blob/master/img/logo.png)

This Swift package is a lightweight wrapper for OVH APIs. That's the easiest way to use OVH.com APIs in your Swift applications.

## Platforms

iOS, OSX, tvOS, watchOS

## Requirements

### System

- iOS 8.0+ / Mac OS X 10.10+ / tvOS 9.0+ / watchOS 2.0+
- Xcode 8.0+

### Swift

This package only supports Swift > 3.0. To support older versions of Swift, please check out the older versions of this project.

### Dependencies

Swift-OVH depends of [Alamofire](https://github.com/Alamofire/Alamofire) and [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift).

## Installation

> **Embedded frameworks require a minimum deployment target of iOS 8.0 or OS X Yosemite (10.9).**

### Carthage

- You can install [Carthage](https://github.com/Carthage/Carthage) with [Homebrew](http://brew.sh/):

```bash
$ sudo brew update
$ sudo brew install carthage
```

- Create a [Cartfile](https://github.com/Carthage/Carthage/blob/master/Documentation/Artifacts.md#cartfile) at the root of your Xcode project:

```bash
github "ovh/swift-ovh"
```

- Run the command `carthage update`, the Swift-OVH framework and its dependencies will be downloaded and built.

- Drag the files `Carthage/Build/[platform]/*.framework` into your Xcode project.

![Drag frameworks](https://github.com/ovh/swift-ovh/blob/master/img/installation-carthage-addframework.png)

- Go to the "Build Phases" panel, create a Run Script with the following contents:

```bash
/usr/local/bin/carthage copy-frameworks
```

and add the paths to the frameworks under “Input Files”, e.g.:

```
$(SRCROOT)/Carthage/Build/iOS/OVHAPIWrapper.framework
$(SRCROOT)/Carthage/Build/iOS/Alamofire.framework
$(SRCROOT)/Carthage/Build/iOS/CryptoSwift.framework
```

![Build phases](https://github.com/ovh/swift-ovh/blob/master/img/installation-carthage-buildphases.png)

### Manually (embedded framework)

- Your project must be initialized as a git repository, if not open up a Terminal console, go to your project folder:

```bash
$ git init
```

- Add Swift-OVH as a git [submodule](http://git-scm.com/docs/git-submodule). As Swift-OVH is depending of git submodules itself, you must update the submodules too.

```bash
$ git submodule add https://github.com/ovh/swift-ovh.git
$ git submodule update --init --recursive
```

- Drag the file `swift-ovh/OVHAPIWrapper.xcodeproj` into the Project Navigator of your application's Xcode project.

![Add dependent project](https://github.com/ovh/swift-ovh/blob/master/img/installation-manually-addproject.png)

- Go to the "General" panel and for each target of your project, add the corresponding `OVHAPIWrapper.framework` as an "Embedding Binaries".

![Add framework](https://github.com/ovh/swift-ovh/blob/master/img/installation-manually-addframework.png)

- The framework must appear under the sections "Embedding Binaries" and "Linked Frameworks and Libraries".

![Embed framework](https://github.com/ovh/swift-ovh/blob/master/img/installation-manually-embedframework.png)

- Go to the "Build Phases" panel, the framework must appear under the sections "Target dependencies" and "Embed Frameworks".

![Build phases](https://github.com/ovh/swift-ovh/blob/master/img/installation-manually-buildphases.png)

- Done! Now you can compile your project with Swift-OVH as a dependency.

## Usage

### Application credentials

First you must ask for application credentials. See the section "Supported APIs", and go to the corresponding url to request your application credentials.

### Initialize the wrapper

- Your application credentials must be set in the constructor of the wrapper object.

```swift
import OVHAPIWrapper

let OVHAPI = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: "[YOUR APPLICATION KEY]", applicationSecret: "[YOUR APPLICATION SECRET]")
```

- By default the latest endpoint version is used. The endpoint version can be defined in the constructor.

```swift
import OVHAPIWrapper

let OVHAPI = OVHAPIWrapper(endpoint: .OVHEU, endpointVersion: "1.0", applicationKey: "[YOUR APPLICATION KEY]", applicationSecret: "[YOUR APPLICATION SECRET]")
```

- If a consumer key is already defined, you can add it to the parameters of the constructor.

```swift
import OVHAPIWrapper

let OVHAPI = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: "[YOUR APPLICATION KEY]", applicationSecret: "[YOUR APPLICATION SECRET]", consumerKey: "[YOUR CONSUME KEY]")
```

### Request the consumer token

- To access to the informations of an OVH account, your application must request a consumer key and the user must validate it. A web page will be presented to the user to validate this consumer key.

> The web page is redirected to the url `redirectionUrl` as soon as the consumer key is validated.

```swift
// This is a shorthand to get all the rights on all the API.
let accessRules = OVHAPIAccessRule.allRights()

// Request a token to the API and return a view controller.
OVHAPI.requestCredentials(withAccessRules: accessRules, redirection: "[YOU URL]", andCompletion: { (viewController, error) -> Void in
    guard error == nil else {
        // Handle the error here.
        return
    }

    if let viewController = viewController {
        // You must define a completion block to know if the consumer key is validated or not.
        viewController.completion = { consumerKeyIsValidated in
            // The consumer key is validated, now the application can call the other APIs.
        }

        // The application is responsible to present the view controller to the user.
        self.present(viewController, animated: true, completion: nil)
    }
})
```

- If you want to handle yourself the `validationUrl`, use the following method. You are responsible to display the page with the url `validationUrl` to the user.

```swift
// This is a shorthand to get the read-only rights on all the API.
let accessRules = OVHAPIAccessRule.readOnlyRights()

// Request a token to the API and return a validation url.
OVHAPI.requestCredentials(withAccessRules: accessRules, redirection: "[YOU URL]") { (consumerKey, validationUrl, error, request, response) -> Void in
    guard error == nil else {
        // Handle the error here.
        return
    }

    guard validationUrl != nil else {
    // If 'validationUrl' is nil, look at the 'response' object.
        return
    }

    // You are responsible to display the page with the url 'validationUrl' to the user.
}
```

- Some access rules must be provided to the credentials request. These rules represent the rights that the user give to your application. You can build these rules manually or using shorthands.

```swift
// Manually build rules: read rights (with GET method) on all the API, and rights to POST on all the sub-API "/vps/".
let accessRules = [OVHAPIAccessRule(method: .get, path: "/*"), OVHAPIAccessRule(method: .post, path: "/vps/*")]

// Equivalent to [OVHAPIAccessRule(method: .get, path: "/*")]
let accessRules = OVHAPIAccessRule.readOnlyRights()

// Equivalent to [OVHAPIAccessRule(method: .get, path: "/vps/*")]
let accessRules = OVHAPIAccessRule.readOnlyRights(forPath: "/vps/*")

// Equivalent to [OVHAPIAccessRule(method: .get, path: "/*"), OVHAPIAccessRule(method: .post, path: "/*"), OVHAPIAccessRule(method: .put, path: "/*"), OVHAPIAccessRule(method: .delete, path: "/*")]
let accessRules = OVHAPIAccessRule.allRights()

// Equivalent to [OVHAPIAccessRule(method: .get, path: "/vps/*"), OVHAPIAccessRule(method: .post, path: "/vps/*"), OVHAPIAccessRule(method: .put, path: "/vps/*"), OVHAPIAccessRule(method: .delete, path: "/vps/*")]
let accessRules = OVHAPIAccessRule.allRights(forPath: "/vps/*")
```

### Request API

- Once the consumer key is validated, all the API can be called. Here the list of VPS is requested.

```swift
OVHAPI.get("/vps") { (result, error, request, response) -> Void in
    guard error == nil else {
        // Handle the error here.
        return
    }

    // Result is an 'Any?' object, it is a JSON deserialization result.
    // So 'result' may be a NSArray object or a NSDictionary object.
    // If 'result' is nil, look at the 'response' object.
}
```

- Another example, enable network burst on SGB1 servers.

```swift
OVHAPI.get("/dedicated/server") { (result, error, request, response) -> Void in
    guard error == nil else {
        // Handle the error here.
        return
    }

    guard let servers = result as? [String] else {
        // Handle the error here.
        return
    }

    // Iterate the servers to get the details.
    for server in servers {
        OVHAPI.get("/dedicated/server/\(server)") { (result, error, request, response) -> Void in
            guard error == nil else {
                // Handle the error here.
                return
            }

            guard let details = result as? NSDictionary else {
                // Handle the error here.
                return
            }

            if let datacenter = details["datacenter"] as? String, datacenter == "sbg1" {
                // Enable network burst.
                OVHAPI.put("/dedicated/server/\(server)/burst", content: ["status":"active" as AnyObject]) { (result, error, request, response) -> Void in
                    guard error == nil else {
                        // Handle the error here.
                        return
                    }

                    // Server is burst.
                    print("We burst \(server).")
                }
            }
        }
    }
}
```

> OVHAPIWrapper defines the methods `get`, `post`, `delete` and `put`.

> All the completion blocks are called in the main thread.

## Run tests

In order to run the tests of the `OVHAPIWrapper` project, you have to copy the file `Tests/Resources/Credentials-Sample.plist` to `Tests/Resources/Credentials.plist` and to set the application key, application secret and consumer key relative to your own application (OVH Europe).

## Run examples

In order to run the examples of the `OVHAPIWrapper` project, you have to copy the file `Examples/OVHAPIWrapper-Example-*/OVHAPIWrapper-Example-*/Resources/Credentials-Sample.plist` to `Examples/OVHAPIWrapper-Example-*/OVHAPIWrapper-Example-*/Resources/Credentials.plist` and to set the application key, application secret and consumer key relative to your own application (OVH Europe).

Supported APIs
--------------

## OVH Europe

 * Documentation: https://eu.api.ovh.com/
 * Community support: api-subscribe@ml.ovh.net
 * Console: https://eu.api.ovh.com/console
 * Create application credentials: https://eu.api.ovh.com/createApp/
 * Create script credentials (all keys at once): https://eu.api.ovh.com/createToken/

## OVH North America

 * Documentation: https://ca.api.ovh.com/
 * Community support: api-subscribe@ml.ovh.net
 * Console: https://ca.api.ovh.com/console
 * Create application credentials: https://ca.api.ovh.com/createApp/
 * Create script credentials (all keys at once): https://ca.api.ovh.com/createToken/

## So you Start Europe

 * Documentation: https://eu.api.soyoustart.com/
 * Community support: api-subscribe@ml.ovh.net
 * Console: https://eu.api.soyoustart.com/console/
 * Create application credentials: https://eu.api.soyoustart.com/createApp/
 * Create script credentials (all keys at once): https://eu.api.soyoustart.com/createToken/

## So you Start North America

 * Documentation: https://ca.api.soyoustart.com/
 * Community support: api-subscribe@ml.ovh.net
 * Console: https://ca.api.soyoustart.com/console/
 * Create application credentials: https://ca.api.soyoustart.com/createApp/
 * Create script credentials (all keys at once): https://ca.api.soyoustart.com/createToken/

## Kimsufi Europe

 * Documentation: https://eu.api.kimsufi.com/
 * Community support: api-subscribe@ml.ovh.net
 * Console: https://eu.api.kimsufi.com/console/
 * Create application credentials: https://eu.api.kimsufi.com/createApp/
 * Create script credentials (all keys at once): https://eu.api.kimsufi.com/createToken/

## Kimsufi North America

 * Documentation: https://ca.api.kimsufi.com/
 * Community support: api-subscribe@ml.ovh.net
 * Console: https://ca.api.kimsufi.com/console/
 * Create application credentials: https://ca.api.kimsufi.com/createApp/
 * Create script credentials (all keys at once): https://ca.api.kimsufi.com/createToken/

## Runabove

 * Documentation: https://community.runabove.com/kb/en/instances/how-to-use-runabove-api.html
 * Community support: https://community.runabove.com
 * Console: https://api.runabove.com/console/
 * Create application credentials: https://api.runabove.com/createApp/

## Related links

 * Contribute: https://github.com/ovh/swift-ovh
 * Report bugs: https://github.com/ovh/swift-ovh/issues

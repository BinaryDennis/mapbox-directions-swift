import Foundation

typealias JSONDictionary = [String: Any]

/// Indicates that an error occurred in MapboxDirections.
public let MBDirectionsErrorDomain = "com.mapbox.directions.ErrorDomain"


/// The user agent string for any HTTP requests performed directly within this library.
let userAgent: String = {
    var components: [String] = []
    
    if let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        components.append("\(appName)/\(version)")
    }
    
    let libraryBundle: Bundle? = Bundle(for: Directions.self)
    
    if let libraryName = libraryBundle?.infoDictionary?["CFBundleName"] as? String, let version = libraryBundle?.infoDictionary?["CFBundleShortVersionString"] as? String {
        components.append("\(libraryName)/\(version)")
    }
    
    let system: String
    #if os(OSX)
    system = "macOS"
    #elseif os(iOS)
    system = "iOS"
    #elseif os(watchOS)
    system = "watchOS"
    #elseif os(tvOS)
    system = "tvOS"
    #elseif os(Linux)
    system = "Linux"
    #endif
    let systemVersion = ProcessInfo().operatingSystemVersion
    components.append("\(system)/\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)")
    
    let chip: String
    #if arch(x86_64)
    chip = "x86_64"
    #elseif arch(arm)
    chip = "arm"
    #elseif arch(arm64)
    chip = "arm64"
    #elseif arch(i386)
    chip = "i386"
    #endif
    components.append("(\(chip))")
    
    return components.joined(separator: " ")
}()

/**
 A `Directions` object provides you with optimal directions between different locations, or waypoints. The directions object passes your request to the [Mapbox Directions API](https://docs.mapbox.com/api/navigation/#directions) and returns the requested information to a closure (block) that you provide. A directions object can handle multiple simultaneous requests. A `RouteOptions` object specifies criteria for the results, such as intermediate waypoints, a mode of transportation, or the level of detail to be returned.
 
 Each result produced by the directions object is stored in a `Route` object. Depending on the `RouteOptions` object you provide, each route may include detailed information suitable for turn-by-turn directions, or it may include only high-level information such as the distance, estimated travel time, and name of each leg of the trip. The waypoints that form the request may be conflated with nearby locations, as appropriate; the resulting waypoints are provided to the closure.
 */
open class Directions: NSObject {
    /**
     A closure (block) to be called when a directions request is complete.
     
     - parameter waypoints: An array of `Waypoint` objects. Each waypoint object corresponds to a `Waypoint` object in the original `RouteOptions` object. The locations and names of these waypoints are the result of conflating the original waypoints to known roads. The waypoints may include additional information that was not specified in the original waypoints.
     
     If the request was canceled or there was an error obtaining the routes, this argument may be `nil`.
     - parameter routes: An array of `Route` objects. The preferred route is first; any alternative routes come next if the `RouteOptions` object’s `includesAlternativeRoutes` property was set to `true`. The preferred route depends on the route options object’s `profileIdentifier` property.
     
     If the request was canceled or there was an error obtaining the routes, this argument is `nil`. This is not to be confused with the situation in which no results were found, in which case the array is present but empty.
     - parameter error: The error that occurred, or `nil` if the placemarks were obtained successfully.
     */
    public typealias RouteCompletionHandler = (_ response: RouteResponse, _ error: DirectionsError?) -> Void
    
    /**
     A closure (block) to be called when a map matching request is complete.
     
     If the request was canceled or there was an error obtaining the matches, this argument is `nil`. This is not to be confused with the situation in which no matches were found, in which case the array is present but empty.
     - parameter error: The error that occurred, or `nil` if the placemarks were obtained successfully.
     */
    public typealias MatchCompletionHandler = (_ response: MapMatchingResponse, _ error: DirectionsError?) -> Void
    
    // MARK: Creating a Directions Object
    
    /**
     The shared directions object.
     
     To use this object, a Mapbox [access token](https://docs.mapbox.com/help/glossary/access-token/) should be specified in the `MGLMapboxAccessToken` key in the main application bundle’s Info.plist.
     */
    public static let shared = Directions()
    
    public let credentials: DirectionsCredentials
    
    /**
     Initializes a newly created directions object with an optional access token and host.
     
     - parameter accessToken: A Mapbox [access token](https://docs.mapbox.com/help/glossary/access-token/). If an access token is not specified when initializing the directions object, it should be specified in the `MGLMapboxAccessToken` key in the main application bundle’s Info.plist.
     - parameter host: An optional hostname to the server API. The [Mapbox Directions API](https://docs.mapbox.com/api/navigation/#directions) endpoint is used by default.
     */
    public init(credentials:  DirectionsCredentials = .init()) {
        self.credentials = credentials
    }
    
    
    // MARK: Getting Directions
    
    /**
     Begins asynchronously calculating routes using the given options and delivers the results to a closure.
     
     This method retrieves the routes asynchronously from the [Mapbox Directions API](https://www.mapbox.com/api-documentation/navigation/#directions) over a network connection. If a connection error or server error occurs, details about the error are passed into the given completion handler in lieu of the routes.
     
     Routes may be displayed atop a [Mapbox map](https://www.mapbox.com/maps/).
     
     - parameter options: A `RouteOptions` object specifying the requirements for the resulting routes.
     - parameter completionHandler: The closure (block) to call with the resulting routes. This closure is executed on the application’s main thread.
     - returns: The data task used to perform the HTTP request. If, while waiting for the completion handler to execute, you no longer want the resulting routes, cancel this task.
     */
    @discardableResult open func calculate(_ options: RouteOptions, completionHandler: @escaping RouteCompletionHandler /* FIXME: VARIENT TYPE */) -> URLSessionDataTask {
        options.fetchStartDate = Date()
        let request = urlRequest(forCalculating: options)
        let requestTask = URLSession.shared.dataTask(with: request) { (possibleData, possibleResponse, possibleError) in
            guard let response = possibleResponse, ["application/json", "text/html"].contains(response.mimeType), let httpResponse = response as? HTTPURLResponse else {
                let response = RouteResponse(httpResponse: possibleResponse as? HTTPURLResponse, options: .route(options), credentials: self.credentials)
                completionHandler(response, .invalidResponse(possibleResponse))
                return
            }
            
            guard let data = possibleData else {
                let response = RouteResponse(httpResponse: httpResponse, options: .route(options), credentials: self.credentials)
                completionHandler(response, .noData)
                return
            }
            
            if let error = possibleError {
                let response = RouteResponse(httpResponse: httpResponse, options: .route(options), credentials: self.credentials)
                let unknownError = DirectionsError.unknown(response: possibleResponse, underlying: error, code: nil, message: nil)
                completionHandler(response, unknownError)
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let decoder = JSONDecoder()
                    decoder.userInfo = [.options: options,
                                        .credentials: self.credentials]
                    
                    guard let disposition = try? decoder.decode(ResponseDisposition.self, from: data) else {
                        let apiError = DirectionsError(code: nil, message: nil, response: possibleResponse, underlyingError: possibleError)
                        let response = RouteResponse(httpResponse: httpResponse, options: .route(options), credentials: self.credentials)

                        DispatchQueue.main.async {
                            completionHandler(response, apiError)
                        }
                        return
                    }
                    
                    guard (disposition.code == nil && disposition.message == nil) || disposition.code == "Ok" else {
                        let apiError = DirectionsError(code: disposition.code, message: disposition.message, response: response, underlyingError: possibleError)
                        let response = RouteResponse(httpResponse: httpResponse, options: .route(options), credentials: self.credentials)

                        DispatchQueue.main.async {
                            completionHandler(response, apiError)
                        }
                        return
                    }
                    
                    let result = try decoder.decode(RouteResponse.self, from: data)
                    guard result.routes != nil else {
                        DispatchQueue.main.async {
                            completionHandler(result, .unableToRoute)
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        completionHandler(result, nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        let bailError = DirectionsError(code: nil, message: nil, response: response, underlyingError: error)
                        let response = RouteResponse(httpResponse: httpResponse, options: .route(options), credentials: self.credentials)
                        completionHandler(response, bailError)
                    }
                }
            }
        }
        requestTask.priority = 1
        requestTask.resume()
        
        return requestTask
    }
    
    /**
     Begins asynchronously calculating matches using the given options and delivers the results to a closure.
     
     This method retrieves the matches asynchronously from the [Mapbox Map Matching API](https://docs.mapbox.com/api/navigation/#map-matching) over a network connection. If a connection error or server error occurs, details about the error are passed into the given completion handler in lieu of the routes.
     
     To get `Route`s based on these matches, use the `calculateRoutes(matching:completionHandler:)` method instead.
     
     - parameter options: A `MatchOptions` object specifying the requirements for the resulting matches.
     - parameter completionHandler: The closure (block) to call with the resulting matches. This closure is executed on the application’s main thread.
     - returns: The data task used to perform the HTTP request. If, while waiting for the completion handler to execute, you no longer want the resulting matches, cancel this task.
     */
    @discardableResult open func calculate(_ options: MatchOptions, completionHandler: @escaping MatchCompletionHandler) -> URLSessionDataTask {
        options.fetchStartDate = Date()
        let request = urlRequest(forCalculating: options)
        let requestTask = URLSession.shared.dataTask(with: request) { (possibleData, possibleResponse, possibleError) in
            guard let response = possibleResponse, response.mimeType == "application/json", let httpResponse = response as? HTTPURLResponse else {
                let result = MapMatchingResponse(httpResponse: possibleResponse as? HTTPURLResponse, options: options, credentials: self.credentials)
                completionHandler(result, .invalidResponse(possibleResponse))
                return
            }
            
            guard let data = possibleData else {
                let result = MapMatchingResponse(httpResponse: httpResponse, options: options, credentials: self.credentials)
                return completionHandler(result, .noData)
            }
            
            if let error = possibleError {
                let unknownError = DirectionsError.unknown(response: possibleResponse, underlying: error, code: nil, message: nil)
                let response = MapMatchingResponse(httpResponse: httpResponse, options: options, credentials: self.credentials)
                completionHandler(response, unknownError)
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let decoder = JSONDecoder()
                    decoder.userInfo = [.options: options,
                                        .credentials: self.credentials]
                    guard let disposition = try? decoder.decode(ResponseDisposition.self, from: data) else {
                          let apiError = DirectionsError(code: nil, message: nil, response: possibleResponse, underlyingError: possibleError)
                          let response = MapMatchingResponse(httpResponse: httpResponse, options: options, credentials: self.credentials)

                          DispatchQueue.main.async {
                              completionHandler(response, apiError)
                          }
                          return
                      }
                      
                      guard disposition.code == "Ok" else {
                          let apiError = DirectionsError(code: disposition.code, message: disposition.message, response: response, underlyingError: possibleError)
                          let response = MapMatchingResponse(httpResponse: httpResponse, options: options, credentials: self.credentials)

                          DispatchQueue.main.async {
                              completionHandler(response, apiError)
                          }
                          return
                      }
                    
                    let result = try decoder.decode(MapMatchingResponse.self, from: data)
                    
                    guard result.matches != nil else {
                        DispatchQueue.main.async {
                            completionHandler(result, .unableToRoute)
                        }
                        return
                    }
                                        
                    DispatchQueue.main.async {
                        completionHandler(result, nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        let caughtError = DirectionsError.unknown(response: response, underlying: error, code: nil, message: nil)
                        let result = MapMatchingResponse(httpResponse: httpResponse, options: options, credentials: self.credentials)
                        completionHandler(result, caughtError)
                    }
                }
            }
        }
        requestTask.priority = 1
        requestTask.resume()
        
        return requestTask
    }
    
    /**
     Begins asynchronously calculating routes that match the given options and delivers the results to a closure.
     
     This method retrieves the routes asynchronously from the [Mapbox Map Matching API](https://docs.mapbox.com/api/navigation/#map-matching) over a network connection. If a connection error or server error occurs, details about the error are passed into the given completion handler in lieu of the routes.
     
     To get the `Match`es that these routes are based on, use the `calculate(_:completionHandler:)` method instead.
     
     - parameter options: A `MatchOptions` object specifying the requirements for the resulting match.
     - parameter completionHandler: The closure (block) to call with the resulting routes. This closure is executed on the application’s main thread.
     - returns: The data task used to perform the HTTP request. If, while waiting for the completion handler to execute, you no longer want the resulting routes, cancel this task.
     */
    @discardableResult open func calculateRoutes(matching options: MatchOptions, completionHandler: @escaping RouteCompletionHandler) -> URLSessionDataTask {
        options.fetchStartDate = Date()
        let request = urlRequest(forCalculating: options)
        let requestTask = URLSession.shared.dataTask(with: request) { (possibleData, possibleResponse, possibleError) in
            guard let response = possibleResponse, ["application/json", "text/html"].contains(response.mimeType), let httpResponse = response as? HTTPURLResponse else {
                let response = RouteResponse(httpResponse: possibleResponse as? HTTPURLResponse, options: .match(options), credentials: self.credentials)
                completionHandler(response, .invalidResponse(possibleResponse))
                return
            }
            
            guard let data = possibleData else {
                let response = RouteResponse(httpResponse: httpResponse, options: .match(options), credentials: self.credentials)
                completionHandler(response, .noData)
                return
            }
            
            if let error = possibleError {
                let response = RouteResponse(httpResponse: httpResponse, options: .match(options), credentials: self.credentials)
                let unknownError = DirectionsError.unknown(response: possibleResponse, underlying: error, code: nil, message: nil)
                completionHandler(response, unknownError)
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let decoder = JSONDecoder()
                    decoder.userInfo = [.options: options,
                                        .credentials: self.credentials]
                    
                    
                    guard let disposition = try? decoder.decode(ResponseDisposition.self, from: data) else {
                        let apiError = DirectionsError(code: nil, message: nil, response: possibleResponse, underlyingError: possibleError)
                        let response = RouteResponse(httpResponse: httpResponse, options: .match(options), credentials: self.credentials)
                        
                        DispatchQueue.main.async {
                            completionHandler(response, apiError)
                        }
                        return
                    }
                    
                    guard disposition.code == "Ok" else {
                        let apiError = DirectionsError(code: disposition.code, message: disposition.message, response: response, underlyingError: possibleError)
                        let response = RouteResponse(httpResponse: httpResponse, options: .match(options), credentials: self.credentials)
                        
                        DispatchQueue.main.async {
                            completionHandler(response, apiError)
                        }
                        return
                    }
                    
                    let result = try decoder.decode(MapMatchingResponse.self, from: data)
                    
                    let routeResponse = RouteResponse(matching: result, options: options, credentials: self.credentials)
                    guard disposition.code == "Ok" else {
                        let apiError = DirectionsError(code: disposition.code, message: disposition.message, response: response, underlyingError: possibleError)
                        DispatchQueue.main.async {
                            completionHandler(routeResponse, apiError)
                        }
                        return
                    }
                    
                    guard routeResponse.routes != nil else {
                        DispatchQueue.main.async {
                            completionHandler(routeResponse, .unableToRoute)
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        completionHandler(routeResponse, nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        let bailError = DirectionsError(code: nil, message: nil, response: response, underlyingError: error)
                        let response = RouteResponse(httpResponse: httpResponse, options: .match(options), credentials: self.credentials)
                        completionHandler(response, bailError)
                    }
                }
            }
        }
        requestTask.priority = 1
        requestTask.resume()
        
        return requestTask
    }
    
    /**
     The GET HTTP URL used to fetch the routes from the API.
     
     After requesting the URL returned by this method, you can parse the JSON data in the response and pass it into the `Route.init(json:waypoints:profileIdentifier:)` initializer. Alternatively, you can use the `calculate(_:options:)` method, which automatically sends the request and parses the response.
     
     - parameter options: A `DirectionsOptions` object specifying the requirements for the resulting routes.
     - returns: The URL to send the request to.
     */
    open func url(forCalculating options: DirectionsOptions) -> URL {
        return url(forCalculating: options, httpMethod: "GET")
    }
    
    /**
     The HTTP URL used to fetch the routes from the API using the specified HTTP method.
     
     The query part of the URL is generally suitable for GET requests. However, if the URL is exceptionally long, it may be more appropriate to send a POST request to a URL without the query part, relegating the query to the body of the HTTP request. Use the `urlRequest(forCalculating:)` method to get an HTTP request that is a GET or POST request as necessary.
     
     After requesting the URL returned by this method, you can parse the JSON data in the response and pass it into the `Route.init(json:waypoints:profileIdentifier:)` initializer. Alternatively, you can use the `calculate(_:options:)` method, which automatically sends the request and parses the response.
     
     - parameter options: A `DirectionsOptions` object specifying the requirements for the resulting routes.
     - parameter httpMethod: The HTTP method to use. The value of this argument should match the `URLRequest.httpMethod` of the request you send. Currently, only GET and POST requests are supported by the API.
     - returns: The URL to send the request to.
     */
    open func url(forCalculating options: DirectionsOptions, httpMethod: String) -> URL {
        let includesQuery = httpMethod != "POST"
        var params = (includesQuery ? options.urlQueryItems : [])
        params += [URLQueryItem(name: "access_token", value: credentials.accessToken)]
        
        if let skuToken = credentials.skuToken {
            params += [URLQueryItem(name: "sku", value: skuToken)]
        }
        
        let unparameterizedURL = URL(string: includesQuery ? options.path : options.abridgedPath, relativeTo: credentials.host)!
        var components = URLComponents(url: unparameterizedURL, resolvingAgainstBaseURL: true)!
        components.queryItems = params
        return components.url!
    }
    
    /**
     The HTTP request used to fetch the routes from the API.
     
     The returned request is a GET or POST request as necessary to accommodate URL length limits.
     
     After sending the request returned by this method, you can parse the JSON data in the response and pass it into the `Route.init(json:waypoints:profileIdentifier:)` initializer. Alternatively, you can use the `calculate(_:options:)` method, which automatically sends the request and parses the response.
     
     - parameter options: A `DirectionsOptions` object specifying the requirements for the resulting routes.
     - returns: A GET or POST HTTP request to calculate the specified options.
     */
    open func urlRequest(forCalculating options: DirectionsOptions) -> URLRequest {
        let getURL = self.url(forCalculating: options, httpMethod: "GET")
        var request = URLRequest(url: getURL)
        if getURL.absoluteString.count > MaximumURLLength {
            request.url = url(forCalculating: options, httpMethod: "POST")
            
            let body = options.httpBody.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.httpBody = body
        }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}

public extension CodingUserInfoKey {
    static let options = CodingUserInfoKey(rawValue: "com.mapbox.directions.coding.routeOptions")!
    static let httpResponse = CodingUserInfoKey(rawValue: "com.mapbox.directions.coding.httpResponse")!
    static let credentials = CodingUserInfoKey(rawValue: "com.mapbox.directions.coding.credentials")!
    static let tracepoints = CodingUserInfoKey(rawValue: "com.mapbox.directions.coding.tracepoints")!


}

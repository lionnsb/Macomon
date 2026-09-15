import CoreLocation
import Foundation

final class EnvironmentReactionController: NSObject, CLLocationManagerDelegate {
    private struct WeatherResponse: Decodable {
        let current: CurrentWeather
    }

    private struct CurrentWeather: Decodable {
        let temperature2m: Double
        let precipitation: Double
        let rain: Double
        let showers: Double
        let snowfall: Double
        let weatherCode: Int
        let windSpeed10m: Double

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case precipitation
            case rain
            case showers
            case snowfall
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
        }
    }

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var weather: CurrentWeather?
    private var lastWeatherRequest: Date = .distantPast
    private var isRunning = false

    var onCandidatesChange: (([String]) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func start() {
        guard !isRunning else {
            publishCandidates()
            return
        }
        isRunning = true
        publishCandidates()
        requestWeatherLocationIfNeeded(force: true)

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.publishCandidates()
            self.requestWeatherLocationIfNeeded(force: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        onCandidatesChange?([])
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRunning else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        fetchWeather(at: location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        publishCandidates()
    }

    private func requestWeatherLocationIfNeeded(force: Bool) {
        guard force || Date().timeIntervalSince(lastWeatherRequest) >= 30 * 60 else { return }
        lastWeatherRequest = Date()

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            publishCandidates()
        @unknown default:
            break
        }
    }

    private func fetchWeather(at coordinate: CLLocationCoordinate2D) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,precipitation,rain,showers,snowfall,weather_code,wind_speed_10m"
            ),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard
                let self,
                let data,
                let response = try? JSONDecoder().decode(WeatherResponse.self, from: data)
            else { return }

            DispatchQueue.main.async {
                self.weather = response.current
                self.publishCandidates()
            }
        }.resume()
    }

    private func publishCandidates() {
        guard isRunning else { return }
        onCandidatesChange?(weatherCandidates() + timeCandidates())
    }

    private func weatherCandidates() -> [String] {
        guard let weather else { return [] }
        let code = weather.weatherCode

        if (95...99).contains(code) {
            return ["storm", "thunderstorm", "thunder", "scared", "rain", "umbrella", "wet"]
        }
        if weather.snowfall > 0 || (71...86).contains(code) {
            return ["snow", "snowy", "cold"]
        }
        if weather.rain + weather.showers + weather.precipitation > 0
            || (51...67).contains(code)
            || (80...82).contains(code) {
            return ["rain", "rainy", "umbrella", "wet"]
        }
        if code == 45 || code == 48 {
            return ["fog", "foggy"]
        }
        if weather.windSpeed10m >= 40 {
            return ["wind", "windy"]
        }
        if weather.temperature2m <= 0 {
            return ["cold", "freezing"]
        }
        if weather.temperature2m >= 30 {
            return ["hot", "heat"]
        }
        if (1...3).contains(code) {
            return ["cloudy", "clouds"]
        }
        if code == 0 {
            return ["sunny", "sun"]
        }
        return []
    }

    private func timeCandidates() -> [String] {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<7, 22..<24:
            return ["night", "sleep", "sleep_zzz"]
        case 7..<11:
            return ["morning", "wake", "wakeup", "stretch"]
        case 18..<22:
            return ["evening", "sunset", "sleepy", "sit"]
        default:
            return ["day"]
        }
    }
}

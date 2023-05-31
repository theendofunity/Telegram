//
//  TimeFetcher.swift
//  Telegram
//
//  Created by Дмитрий Дудкин on 30.05.2023.
//

import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore

final class TimeFetcher {
    private let url = "https://worldtimeapi.org/api/timezone/Europe/Moscow"
    
    func fetchCurrentTime() -> Signal<DateTimeEntity?, MediaResourceDataFetchError> {
        fetchHttpResource(url: url)
        |> filter({ result in
            guard case let .dataPart(_, _, _, complete) = result, complete else {
                return false
            }
            
            return true
        })
        |> map { [weak self] result in
            switch result {
            case let .dataPart(_, data, _, completed):
                return self?.decodeDateTime(data: data, completed: completed)
            default:
                return nil
            }
        }
    }
    
    private func decodeDateTime(data: Data, completed: Bool) -> DateTimeEntity? {
        guard completed else {
            return nil
        }
        
        return try? JSONDecoder().decode(DateTimeEntity.self, from: data)
    }
}

struct DateTimeEntity: Codable {
    let unixTime: Int32
    
    private enum CodingKeys: String, CodingKey {
        case unixTime = "unixtime"
    }
}

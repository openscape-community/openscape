//
//  OnboardingWelcomeView.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import SwiftUI

struct OnboardingWelcomeView: View {
    
    // MARK: Properties
    
    @EnvironmentObject var viewModel: OnboardingViewModel
    let context: OnboardingBehavior.Context

    @ViewBuilder
    private var destination: some View {
        if shouldSkipLanguageSelection() {
            OnboardingHeadphoneView()
        } else {
            OnboardingLanguageView()
        }
    }
    
    // Determines whether to skip language selection based on device locale, app locale, and user preferences
    private func shouldSkipLanguageSelection() -> Bool {
        let deviceLocale = LocalizationContext.deviceLocale.identifierHyphened
        let appLocale = LocalizationContext.currentAppLocale.identifierHyphened
        
        // Extract language codes for comparison
        let deviceLanguageCode = Locale(identifier: deviceLocale).languageCode
        let appLanguageCode = Locale(identifier: appLocale).languageCode
        
        // Check if languages match (ignoring regional differences) and if the user allows skipping
        if let deviceLanguageCode, let appLanguageCode, deviceLanguageCode == appLanguageCode {
            return !UserSettings.alwaysShowLanguageSelection
        }
        
        return false
    }
    
    // MARK: `body`
    
    var body: some View {
        NavigationView {
            OnboardingContainer(coverImage: Image("permissions-intro"), accessibilityLabel: GDLocalizationUnnecessary("Soundscape")) {
                Spacer()
                
                VStack(spacing: 12.0) {
                    GDLocalizedTextView("first_launch.welcome.title")
                        .onboardingHeaderTextStyle()
                        .accessibilityLabel(GDLocalizedTextView("first_launch.welcome.title.accessibility_label"))
                    
                    GDLocalizedTextView("first_launch.welcome.description")
                        .onboardingTextStyle()
                }
                
                Spacer()
                
                OnboardingNavigationLink(text: GDLocalizedString("first_launch.welcome.button"), destination: destination)
            }
        }
        .accentColor(.primaryForeground)
        .onAppear {
            GDATelemetry.trackScreenView("onboarding.welcome")
            
            // If onboarding has already been completed,
            // then onboarding was started from app settings
            GDATelemetry.track("onboarding.started", with: [ "first_launch": "\(!FirstUseExperience.didComplete(.oobe))"])
            
            AppContext.shared.eventProcessor.activateCustom(behavior: OnboardingBehavior(context: context))
        }
        .onDisappear {
            AppContext.shared.eventProcessor.deactivateCustom()
        }
    }
}

// Mocked UserSettings for demonstration purposes
struct UserSettings {
    static var alwaysShowLanguageSelection: Bool = false // User-configurable setting
}

// MARK: Preview
struct FirstLaunchWelcomeView_Previews: PreviewProvider {
    
    static var previews: some View {
        OnboardingWelcomeView(context: .firstUse)
            .environmentObject(OnboardingViewModel())
    }
}


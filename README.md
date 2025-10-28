## Croissant: Your Daily Essential.

Croissant is a minimalist macOS dashboard designed to start your day right — combining weather, news, calendar events, reminders, system info and nearby public transport departures in one elegant view.

<img src="https://github.com/user-attachments/assets/89f4e92a-4b76-4bbe-a180-775a1b43c460" width="33%"/>
<img src="https://github.com/user-attachments/assets/c8887330-be48-4a8f-9efe-892b6e0449b4" width="33%"/>
<img src="https://github.com/user-attachments/assets/f0724961-991c-40b7-ab9c-5246113e9fad" width="33%"/>


## Important Notes
- The app is currently optimized for use in Germany. Expansion is planned if there is sufficient demand.
- Compatibility tested for macOS Tahoe and above.
- The app has not yet been notarized by Apple, but is fully functional. More information can be found in the Q&A section.

## Required permissions
- Reminders (display reminders in dashboard)
- Calendar (display events in dashboard)
- Location (retrieve weather and traffic data)

I do **not store, sell, or otherwise use any data**. Your data remains on your device. Exception: Your location is used anonymously to retrieve weather and public transport data. 

## Download
You can download "Croissant" here: <a href="https://github.com/Frobotics-dev/Croissant/releases">Latest Release</a> 

## Q&A section
<details>
<summary><strong>Is the app free?</strong></summary>
Yes, the app is completely free and open source. You don't need your own API keys either, as I provide them for you myself. Of course, I would appreciate a small contribution via Buy Me a Coffee :)
  
  <a href="https://www.buymeacoffee.com/frederik.m" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
</details>


<details>
<summary><strong>Is the app open source?</strong></summary>
Yes, you are welcome to look at the code and contribute if you want. Everything can be found on GitHub.
</details>

<details>
<summary><strong>Why isn't it notarized? Should I be concerned?</strong></summary>
Apple requires a subscription model for developers for notarization. However, as a student, I only program free apps for the community, so it's not worth it for me. I understand if you have concerns, but you don't need to worry. The code is open source and accessible to everyone. Feel free to take a look and see for yourself, or help me with development :)
</details>

<details>
<summary><strong>I can't open the app.</strong></summary>
This is because the app is not (yet) notarized (see the previous question). Proceed as follows:
  
1. On your Mac, choose Apple menu > System Settings, then click Privacy & Security  in the sidebar. (You may need to scroll down.)
2. Go to Security, then click Open.
3. Click Open Anyway. This button is available for about an hour after you try to open the app.
4. Enter your login password, then click OK.

</details>

<details>
<summary><strong>How do you handle my data?</strong></summary>
I do not store, sell, or otherwise use any data. Your data remains on your device. Exception: Your location is used anonymously to retrieve weather and public transport data. 
</details>

<details>
<summary><strong>What features does the app include?</strong></summary>
In its current version, the app has six tiles that can be freely selected and arranged: calendar, reminders, weather, departure times from nearby stops, headlines from various news portals, and system information. It also includes smaller features such as a low power indicator and various personalization options. The app is still in beta, but more is planned, e.g., the integration of stock values.
</details>

<details>
<summary><strong>How does it differ from Apple widgets?</strong></summary>
The widgets you can use on the desktop are quite basic, limited in their functionality, and less interactive. Croissant offers a more unified approach with an all-in-one solution that I can expand according to my own ideas.
</details>

<details>
<summary><strong>Can you add support for Google Calendar?</strong></summary>
I don't have any plans to do so at the moment. A fairly simple workaround is to integrate Google Calendar into Apple's Calendar app, which will then automatically load events into Croissant. If you have any further suggestions, please feel free to send me an email using the feedback button in the app.
</details>

<details>
<summary><strong>Which APIs are you using?</strong></summary>

  - v6.db.transport.rest (Deutsche Bahn AG)
  - api.weatherapi.com/v1/forecast.json (Weather API)
  - api.github.com/repos/Frobotics-dev/Croissant/releases (Check for updates)
  - RSS-Feeds (News and headlines)
  - (coming soon) generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent (Google Gemini)
    
</details>

<details>
<summary><strong>Do I need my own API keys?</strong></summary>
No, you don't.
</details>

<details>
<summary><strong>What bugs are known?</strong></summary>
Shortly before and after midnight, connections may be displayed that do not exist. However, you can recognize this by the fact that the departure time is more than 1440 minutes away (and is also displayed as such).
  In rare cases, it may also happen that the views are not reloaded. This error is caused by incorrect location determination. As a workaround, go to Settings > Debugging > Reload View.
</details>

<details>
<summary><strong>How does it all work?</strong></summary>
In addition to the pure programming of logic and user interface, this app also calls external databases on servers. 
  Cloudflare therefore acts as an intermediary “worker” between the macOS app and the Weather API to protect my API key. Clouflare then executes the Get call in a protected manner and passes the JSON to the app.
The Transit API, which is provided by a team of open source developers and processes and makes available data from the Deutsche Bahn API, works in a similar way.
</details>

<details>
<summary><strong>Why is the app called "Croissant"?</strong></summary>
For me, the app is part of my daily morning routine, just like a good croissant is part of breakfast in France. With this in mind, the app gives me a briefing on the day ahead while I enjoy a cup of coffee and, ideally, a croissant: What meetings do I have today? What's happening in the world? When does the next bus to university leave?
</details>

<details>
<summary><strong>Who are you?</strong></summary>
My name is Frederik, I am the developer of the “Croissant” app and I study industrial engineering. On my free evenings, I like to try my hand at Xcode and build apps that I would like to have myself. Since I don't want to make any financial profit from this, I make my apps available to the general public free of charge. Nevertheless, I would of course be very happy to receive a coffee (or a croissant...) to dedicate more time to development, pay for APIs, and push updates that keep Croissant evolving. Thank you!

  You can contact me anytime via the feedback button inside the app settings.
</details>

Your support lets me dedicate more time to development, pay for APIs, and push updates that keep Croissant evolving. If you enjoy what I’m building, consider buying me a coffee — it keeps both me and the app running smoothly.

Thanks for helping turn this student project into something real! :)

<a href="https://www.buymeacoffee.com/frederik.m" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

<!--![AppIcon](https://github.com/user-attachments/assets/ccb8e6de-ef71-4ae5-ac51-63d4d82a8404)-->

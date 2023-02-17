const sundialMottos = [
    "The hour flees, don't be late.",
    "The hour is flowing away.",
    "Time is short.",
    "Time flies, the hour flees.",
    "Devote this hour to work, another to leisure.",
    "Make haste, but slowly.",
    "Use the hours, don't count them.",
    "Use the hour, it will not come again",
    "Beware of one hour.",
    "An hour passes slowly, but the years go by quickly.",
    "All hours wound; the last one kills.",
    "It's later than you think.",
    "Life flows away as it seems to stay the same.",
    "Springtime does not last.",
    "Time conquers everything.",
    "I have seen that nothing under the sun endures.",
    "Remember to live.",
    "Take the gifts of this hour",
    "Enjoy the hour.",
]

document.getElementById("sundial-motto").textContent = sundialMottos.at(
    Math.floor(Math.random() * sundialMottos.length))

const timeElem = document.getElementById("time")
function updateTime() {
    timeElem.textContent = new Date().toLocaleString()
    setTimeout(updateTime, 1000)
}

updateTime()

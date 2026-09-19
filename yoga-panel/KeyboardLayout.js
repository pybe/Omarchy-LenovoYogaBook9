.pragma library

function pair(en, ru, enShift, ruShift) {
    return {en:en, ru:ru, enShift:enShift || en.toUpperCase(), ruShift:ruShift || ru.toUpperCase()};
}
function letters(en, ru) {
    return en.split("").map((key,i)=>pair(key,ru[i]));
}
var numbers = [pair("`","ё","~","Ё"),pair("1","1","!","!"),pair("2","2","@","\""),
    pair("3","3","#","№"),pair("4","4","$",";"),pair("5","5","%","%"),
    pair("6","6","^",":"),pair("7","7","&","?"),pair("8","8","*","*"),
    pair("9","9","(","("),pair("0","0",")",")"),pair("-","-","_","_"),pair("=","=","+","+")];
var upper = letters("qwertyuiop", "йцукенгшщз").concat([pair("[","х","{","Х"),pair("]","ъ","}","Ъ")]);
var middle = letters("asdfghjkl", "фывапролд").concat([pair(";","ж",":","Ж"),pair("'","э","\"","Э")]);
var lower = letters("zxcvbnm", "ячсмить").concat([pair(",","б","<","Б"),pair(".","ю",">","Ю"),pair("/",".","?",",")]);
function character(key, russian, shift, caps) {
    let base=russian ? key.ru : key.en;
    if (/^[a-zа-яё]$/i.test(base)) return shift !== caps ? base.toUpperCase() : base.toLowerCase();
    return shift ? (russian ? key.ruShift : key.enShift) : base;
}

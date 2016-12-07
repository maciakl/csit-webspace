function select_contents(el)
{if(typeof window.getSelection!="undefined"&&typeof document.createRange!="undefined")
{var range=document.createRange();range.selectNodeContents(el);var sel=window.getSelection();sel.removeAllRanges();sel.addRange(range);}
else if(typeof document.selection!="undefined"&&typeof document.body.createTextRange!="undefined")
{var textRange=document.body.createTextRange();textRange.moveToElementText(el);textRange.select();}}
var elements=document.querySelectorAll("code");Array.prototype.forEach.call(elements,function(el,i){el.setAttribute("onclick","select_contents(this)");});


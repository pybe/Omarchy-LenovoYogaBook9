// Exercise the actual production QML JavaScript with recorded-shape touch
// sequences, including the extra stationary contact seen on this machine.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const qml = fs.readFileSync(process.argv[2] || `${__dirname}/shell.qml`, 'utf8');
const start = qml.indexOf('function sample(currentPoints)');
const end = qml.indexOf('onPressed:', start);
assert(start >= 0 && end > start);
const source = qml.slice(start, end);
function harness() {
    const sent = [];
    let now=1000;
    const c = vm.createContext({samples:0, histogram:[0,0,0,0,0,0],
        reversalSamples:{x:0,y:0},reversalStarted:{x:0,y:0},scrollVX:0,scrollVY:0,lastScrollTime:0,velocitySamples:0,scrollDistance:0,momentumStarted:0,momentumLast:0,momentumProgress:0,carryVX:0,carryVY:0,carryUntil:0,
        momentum:{running:false,restart(){this.running=true},stop(){this.running=false}},
        previousCount:0, positions:{}, began:0, travel:0, peakCount:0,
        lastX:0,lastY:0,moveEvents:0,scrollEvents:0,
        lastSampleTime:0,lastTapTime:-1000,lastTapX:0,lastTapY:0,tapDragging:false,dragPointId:-1,
        workspaceGesture:false,focusSwipe:false,swipeX:0,swipeY:0,scrolling:false,pairX:0,pairY:0,scrollDirections:{x:0,y:0},scrollReversals:{x:0,y:0},
        Date:{now:()=>now},
        root:{inertiaStrength:.65,inertiaDuration:650,clearWord:()=>{},drag:false,pointerSpeed:1.5,pointerAccel:0,scrollSpeed:0.6,send:e=>sent.push({...e}),click:b=>sent.push({click:b})}});
    vm.runInContext(source, c);
    return {sample:p=>{now+=16;c.sample(p)},sent,c,advance:t=>now+=t};
}
const p = (pointId,x,y) => ({pointId,x,y,pressed:true});
let h = harness();
h.sample([p(0,100,100)]);
h.sample([p(0,120,100)]);
h.sample([]);
assert.deepEqual(h.sent,[{type:'move',x:30,y:0}]);
h = harness();
h.sample([p(0,100,100),p(1,400,300)]);
h.sample([p(0,120,100),p(1,400,300)]);
assert.deepEqual(h.sent,[{type:'move',x:30,y:0}]);
h = harness();
h.sample([p(0,100,100),p(1,200,100)]);
h.sample([p(0,100,120),p(1,200,120)]);
assert.equal(h.sent[0].type,'scroll');
assert.equal(h.sent[0].y,-12);
h = harness();
h.sample([p(0,100,100)]);
h.sample([p(0,100,100),p(1,400,400)]);
h.sample([p(0,100,100)]);
assert.deepEqual(h.sent,[],'Adding/lifting a stationary finger must not jump');
h = harness();
h.sample([p(0,100,100)]); h.sample([]);
h.sample([p(1,100,100)]); h.sample([p(1,120,100)]); h.sample([]);
assert.deepEqual(h.sent,[{click:272},{type:'button',button:272,state:1},{type:'move',x:30,y:0},{type:'button',button:272,state:0}],'Double tap holds button during motion, releases without an extra click');
h = harness();
h.sample([p(0,100,100)]); h.sample([]);
h.advance(400); h.sample([p(1,100,100)]); h.sample([p(1,120,100)]);
assert.deepEqual(h.sent,[{click:272},{type:'move',x:30,y:0}],'Old tap must not start a drag');
h = harness();
h.sample([p(0,100,100)]); h.sample([]); h.sample([p(1,100,100)]);
h.c.resetGesture();
assert.equal(h.sent.at(-1).state,0,'Cancel releases held button');
assert.equal(h.c.tapDragging,false);
h = harness(); h.c.root.pointerAccel=1;
h.sample([p(0,100,100)]); h.sample([p(0,101,100)]); h.sample([p(0,121,100)]);
assert(h.sent[1].x/20 > h.sent[0].x,'Faster movement gets more gain');
h = harness(); h.c.root.scrollSpeed=0.18;
h.sample([p(0,100,100),p(1,200,100)]); h.sample([p(0,100,120),p(1,200,120)]);
assert(Math.abs(h.sent[0].y+3.6)<1e-9);
console.log('PASS: movement, extra stationary contact, scroll, no jumps, tap-drag, timeout, cancel, acceleration, scroll speed');
h=harness();
h.sample([p(0,100,100)]); h.sample([p(0,100,100),p(1,200,100)]);
h.sample([p(0,100,100)]); h.sample([]);
assert.deepEqual(h.sent,[{click:273}],'Staggered two-finger tap produces only right click');
const three=(x,y=100)=>[p(0,x,y),p(1,x+100,y),p(2,x+200,y)];
for(const [delta,direction] of [[-140,'next'],[140,'previous']]) {
 h=harness();h.sample(three(300));h.sample(three(300+delta));
 h.sample([p(0,300+delta,100),p(1,400+delta,100)]);h.sample([]);
 assert.deepEqual(h.sent,[{type:'workspace',direction}],'Swipe emits once with no pointer movement, scroll or click');
}
for(const [x,y] of [[20,0],[0,20],[130,140]]) {
 h=harness();h.sample(three(300));h.sample(three(300+x,100+y));h.sample([]);
 assert.deepEqual(h.sent,[],'Short or diagonal gestures do nothing');
}
for(const [delta,direction] of [[150,'down'],[-150,'up']]) {
 h=harness();h.sample(three(300));h.sample(three(300,100+delta));
 h.sample([p(0,300,100+delta),p(1,400,100+delta)]);h.sample([]);
 assert.deepEqual(h.sent,[{type:'minimize',direction}],'Vertical swipe minimizes or restores once, without scroll or click');
}
for(const [delta,direction] of [[160,'l'],[-160,'r']]) {
 h=harness();h.sample([p(0,300,100),p(1,300,200)]);
 for(let i=1;i<=8;i++) h.sample([p(0,300+delta*i/8,100),p(1,300+delta*i/8,200)]);
 h.sample([]);
 assert.deepEqual(h.sent.filter(e=>e.type!=='scrollEnd'),[{type:'focus',direction}],'Sideways two-finger stroke moves focus once, without scroll');
}
h=harness();h.sample(three(300));h.sample(three(150));h.c.resetGesture();h.sample([]);
assert.deepEqual(h.sent,[],'Cancel cannot switch workspace');
const keys=vm.createContext({pad:{stopMomentum(){}},predictionEnabled:true,autocorrectEnabled:true,russian:true,lastTypedAt:0,logo:true,shift:true,control:false,alt:false,wordPrefix:"",held:{},used:{},clearWord:()=>{},updateWord:()=>{},send:e=>keys.last=e});
vm.runInContext(qml.slice(qml.indexOf('function typeKey(key)'),qml.indexOf('function click(button)')),keys);
keys.typeKey('Tab');
assert.deepEqual(Array.from(keys.last.mods),['logo','shift']);
assert.equal(keys.logo,false);assert.equal(keys.shift,false);
keys.logo=true;keys.typeText('3');
assert.equal(keys.last.text,'3');assert.deepEqual(Array.from(keys.last.mods),['logo']);
keys.typeText('4');assert.equal(keys.last.mods.length,0,'Super is one-shot');
keys.holdMod('shift',true);keys.shift=true;
keys.typeText('П');keys.typeText('Р');keys.typeKey('Left');
assert.equal(keys.shift,true,'Held Shift stays active for every key');
assert.deepEqual(Array.from(keys.last.mods),['shift']);
keys.holdMod('shift',false);assert.equal(keys.shift,false,'Releasing a used Shift clears it');
keys.holdMod('shift',true);keys.shift=true;keys.holdMod('shift',false);
assert.equal(keys.shift,true,'Tapped Shift remains one-shot');
keys.typeText('П');assert.equal(keys.shift,false);
keys.holdMod('logo',true);keys.logo=true;
keys.typeText('3');keys.typeText('4');
assert.equal(keys.logo,true,'Held Super stays active');assert.deepEqual(Array.from(keys.last.mods),['logo']);
keys.holdMod('control',true);keys.control=true;keys.typeKey('Tab');
assert.deepEqual(Array.from(keys.last.mods).sort(),['ctrl','logo'],'Two held modifiers combine');
keys.holdMod('logo',false);keys.holdMod('control',false);
assert.equal(keys.logo,false);assert.equal(keys.control,false,'Released modifiers clear');
keys.holdMod('alt',true);keys.alt=true;keys.holdMod('alt',false);
assert.equal(keys.alt,true,'Tapped Alt remains one-shot');keys.typeKey('Tab');assert.equal(keys.alt,false);
console.log('PASS: right click, horizontal and vertical swipes, staggered release, rejected gestures, cancel, Super combinations, held modifiers');

h=harness();h.sample([p(0,100,100),p(1,200,100)]);
h.sample([p(0,100,120),p(1,200,120)]);
h.sample([p(0,100,125),p(1,200,120)]);
h.sample([p(0,100,125),p(1,200,125)]);
assert(h.sent.every(e=>e.type==='scroll'),'Scroll remains stable with asynchronous finger updates');
h=harness();h.sample([p(0,100,100)]);h.sample([]);h.sample([p(0,100,100)]);
h.sample([p(0,100,100),p(1,200,100)]);h.sample([p(0,100,120),p(1,200,120)]);
assert.equal(h.c.tapDragging,false);assert.equal(h.sent.at(-1).type,'scroll');
console.log('PASS: stable scrolling and two-finger priority over tap-drag');

h=harness();h.sample([p(0,100,100),p(1,200,100)]);
h.sample([p(0,100,120),p(1,200,120)]);
h.sample([p(0,100,119),p(1,200,119)]);
assert.equal(h.sent.length,1,'Small reverse release jitter is suppressed');
h.sample([p(0,100,115),p(1,200,115)]);
h.sample([p(0,100,108),p(1,200,108)]);
assert(h.sent.at(-1).y>0,'Intentional reverse scrolling still works');
h.sample([p(0,100,110)]);h.sample([]);
assert.equal(h.sent.at(-1).type,'scrollEnd');
assert(!h.sent.some(e=>e.type==='move'),'Lifting scroll fingers never moves pointer');
console.log('PASS: reverse jitter, deliberate reversal, scroll end, no lift-off cursor jump');

h=harness();h.sample([p(0,100,100),p(1,200,100)]);
h.sample([p(0,100,102),p(1,200,102)]);h.sample([]);
assert.deepEqual(h.sent,[{click:273}],'Two px of fingertip settling is a right click, not a scroll');
h=harness();h.sample([p(0,100,100),p(1,200,100)]);
h.sample([p(0,100,103),p(1,200,103)]);h.sample([p(0,100,106),p(1,200,106)]);h.sample([]);
assert(h.sent.some(e=>e.type==='scroll'),'Scroll starts after the dead zone');
assert(!h.sent.some(e=>e.click),'A small scroll must not also right-click');
h=harness();h.sample([p(0,100,100)]);h.sample([p(0,100,101),p(1,200,100)]);
h.sample([p(0,100,102),p(1,200,101.5)]);h.sample([p(1,200,102)]);h.sample([]);
assert.deepEqual(h.sent.filter(e=>e.type!=='move'),[{click:273}],'Late second finger with settling drift still right-clicks');
h=harness();h.sample([p(0,100,100)]);for(let i=0;i<24;i++)h.sample([p(0,100,100),p(1,200,100)]);h.sample([]);
assert.deepEqual(h.sent,[{click:273}],'Unhurried two-finger tap within 450 ms right-clicks');

function flick(h,speed=.09) {
 h.c.root.inertiaEnabled=true;h.c.root.opened=true;h.c.root.scrollSpeed=speed;
 h.sample([p(0,100,100),p(1,200,100)]);
 for(let y=120;y<=180;y+=20)h.sample([p(0,100,y),p(1,200,y)]);
 h.sample([]);
}
h=harness();flick(h);assert.equal(h.c.momentum.running,true);
let distances=[];
while(h.c.momentum.running){h.advance(16);let before=h.sent.length;h.c.tickMomentum();if(h.sent.length>before&&h.sent.at(-1).type==='scroll')distances.push(-h.sent.at(-1).y);}
assert(distances.length>2&&distances.length<100);
assert(distances.every((v,i)=>v>0&&(!i||v<distances[i-1])),'Tail decays without reversal');
assert.equal(h.sent.at(-1).type,'scrollEnd');
h=harness();flick(h);let before=h.sent.length;h.sample([p(0,200,200)]);
assert.equal(h.c.momentum.running,false);assert.equal(h.sent[before].type,'scrollEnd');
h=harness();flick(h);h.c.resetGesture();assert.equal(h.c.momentum.running,false);
h=harness();h.c.root.inertiaEnabled=true;h.c.root.opened=true;
h.sample([p(0,100,100),p(1,200,100)]);h.sample([p(0,100,120),p(1,200,120)]);h.sample([p(0,100,140),p(1,200,140)]);h.advance(100);h.sample([]);
assert.equal(h.c.momentum.running,false,'Pause before release prevents coasting');
h=harness();flick(h);h.advance(1000);h.c.tickMomentum();assert.equal(h.c.momentum.running,false,'A stalled UI cannot emit a jump');
h=harness();h.c.root.scrollSpeed=.09;
h.sample([p(0,100,100),p(1,200,100)]);h.sample([p(0,100,120),p(1,200,120)]);
let first=h.sent.at(-1).y;h.c.root.scrollSpeed=.18;h.sample([p(0,100,140),p(1,200,140)]);
assert(Math.abs(h.sent.at(-1).y-2*first)<1e-9,'Speed changes affect the very next motion');
console.log('PASS: short decaying inertia, immediate touch/cancel stop, paused lift, stalled timer, live sensitivity');

assert(distances.at(-1)<distances[0]*.001,'Last motion approaches zero before scrollEnd');
function tail(duration,strength) {
 let a=harness();flick(a);a.c.root.inertiaDuration=duration;
 // Scale the already captured release velocity as a different strength would.
 a.c.scrollVX*=strength/.65;a.c.scrollVY*=strength/.65;
 let total=0;let frames=0;
 while(a.c.momentum.running){a.advance(16);let before=a.sent.length;a.c.tickMomentum();for(const e of a.sent.slice(before))if(e.type==='scroll')total+=Math.abs(e.y);frames++;}
 return {total,frames};
}
let short=tail(300,.65),long=tail(900,.65),strong=tail(300,1.3);
assert(long.frames>short.frames);assert(Math.abs(long.total/short.total-3)<.001);
assert(Math.abs(strong.total/short.total-2)<.001);
console.log('PASS: continuous stop at zero, configurable duration and strength');

h=harness();flick(h,.0018);assert.equal(h.c.momentum.running,true,"Inertia is available at 1% scroll speed");

// Lift-off drift used to switch the captured velocity after just 4 px.
for (const axis of ['x','y']) for (const sign of [-1,1]) {
 h=harness(); h.c.root.inertiaEnabled=true; h.c.root.opened=true;
 const points=v=>[p(0,axis==='x'?v:100,axis==='y'?v:100),p(1,axis==='x'?v+100:200,axis==='y'?v:100)];
 h.sample(points(100));
 for(const v of [120,140,160,180]) h.sample(points(100+sign*(v-100)));
 const before=h.sent.length;
 h.sample(points(100+sign*75)); h.sample([]);
 while(h.c.momentum.running){h.advance(16);h.c.tickMomentum();}
 assert(!h.sent.slice(before).some(e=>e.type==='scroll'&&e[axis]*sign>0),'Lift-off drift must not launch reverse inertia');
}
console.log('PASS: lift-off reversal regression on both axes and directions');

for (const sign of [-1,1]) {
 h=harness();h.c.root.inertiaEnabled=true;h.c.root.opened=true;
 const points=v=>[p(0,100,100+sign*v),p(1,200,100+sign*v)];
 for(const v of [0,20,40,60,80,74,68,62,56,50])h.sample(points(v));
 h.sample([]);assert(h.c.momentum.running);
 h.advance(16);h.c.tickMomentum();
 assert(h.sent.at(-1).y*sign>0,'Sustained intentional reversal gets matching inertia');
}
console.log('PASS: sustained deliberate reverse scroll retains inertia');

// Animation time is monotonic even if the wall clock jumps; integration must
// preserve distance at variable frame rates instead of adding fixed steps.
function scheduledTail(intervals) {
 const a=harness();flick(a);let t=a.c.momentumStarted, total=0, i=0;
 while(a.c.momentum.running) {
  t+=intervals[i++%intervals.length];
  const begin=a.sent.length;
  a.advance(10000); // Deliberately unrelated wall clock.
  a.c.tickMomentum(t);
  for(const e of a.sent.slice(begin))if(e.type==='scroll')total+=Math.abs(e.y);
  assert(i<200);
 }
 return total;
}
assert(Math.abs(scheduledTail([1000/60])-scheduledTail([8,25,17,16]))<1e-9,
 'Variable display frame times preserve distance and survive wall-clock changes');
assert(scheduledTail([1000/60])>0,'Animation clock actually produces motion');
console.log('PASS: display-frame timing, clock jumps, frame-rate independent distance');

function swipe(a, step=20, interval=16, sign=1) {
 a.c.root.inertiaEnabled=true;a.c.root.opened=true;
 a.sample([p(0,100,100),p(1,200,100)]);
 for(let i=1;i<=5;i++){
  a.advance(interval-16);
  a.sample([p(0,100,100+sign*step*i),p(1,200,100+sign*step*i)]);
 }
 a.sample([]);
 return Math.hypot(a.c.scrollVX,a.c.scrollVY);
}
let slow=harness(),fast=harness();
for(const a of [slow,fast]){a.c.root.scrollSpeed=.9;a.c.root.inertiaStrength=1.5;}
let slowV=swipe(slow,20,32),fastV=swipe(fast,20,8);
assert(fastV>slowV*2,'Fast swipe must launch faster inertia even at high sensitivity');
h=harness();h.c.root.scrollSpeed=.18;
let v1=swipe(h);h.advance(32);h.c.tickMomentum();let v2=swipe(h);
assert(v2>v1*1.2,'Repeated same-direction flick adds remaining momentum');
console.log('PASS: swipe-speed response and repeated flick acceleration');

// Carry is an opportunity for another scroll, never permission to keep moving
// under a resting finger or to pull a reversed swipe in the old direction.
for(const mode of ['opposite','expired','tap','cancel','pointer']) {
 let a=harness();a.c.root.scrollSpeed=.18;swipe(a);
 a.advance(16);a.c.tickMomentum();
 if(mode==='expired'){a.c.interruptMomentumForTouch();a.advance(500);}
 if(mode==='tap'){a.sample([p(0,100,100)]);assert(!a.c.momentum.running);a.sample([]);}
 if(mode==='cancel')a.c.resetGesture();
 if(mode==='pointer'){a.sample([p(0,100,100)]);a.sample([p(0,120,100)]);a.sample([]);}
 const direction=mode==='opposite'?-1:1;
 let actual=swipe(a,20,16,direction);
 let clean=harness();clean.c.root.scrollSpeed=.18;
 let expected=swipe(clean,20,16,direction);
 assert(Math.abs(actual-expected)<1e-9,`${mode} must discard carry`);
}
h=harness();h.c.root.scrollSpeed=.9;h.c.root.inertiaStrength=1.5;
let previous=0;
for(let i=0;i<15;i++){
 let speed=swipe(h,40,8);
 assert(speed>=previous-1e-9,'Repeated same-direction flicks increase speed');
 assert(speed<.9*1.5*8,'Repeated flicks stay bounded');previous=speed;
}

h=harness();flick(h);h.c.root.inertiaDuration=1500;
h.advance(16);h.c.tickMomentum();
let pre=h.sent.length;h.advance(120);h.c.tickMomentum();
assert(h.c.momentum.running,'A delayed frame must not cut off long inertia');
assert(h.sent.slice(pre).filter(e=>e.type==='scroll').length===1);
assert(Math.abs(h.sent.at(-1).y)<=Math.abs(h.c.scrollVY)*32,'No catch-up jump after delayed frame');
let total=h.sent.filter(e=>e.type==='scroll').slice(4).reduce((sum,e)=>sum+Math.abs(e.y),0);
while(h.c.momentum.running){h.advance(16);pre=h.sent.length;h.c.tickMomentum();for(const e of h.sent.slice(pre))if(e.type==='scroll')total+=Math.abs(e.y);}
assert(Math.abs(total-Math.abs(h.c.scrollVY)*1500/4)<1e-8,'Delayed frame preserves the full smooth tail distance');
assert.equal(h.sent.at(-1).type,'scrollEnd');
console.log('PASS: braking, carry expiry, tap/cancel/pointer resets, bounded repeat acceleration, delayed long tail');

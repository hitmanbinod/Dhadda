/* Dev-only demo dataset. Loaded ONLY when the page is opened with ?demo=1.
   Never reads or writes the real store; app.js keeps it in memory. */
window.__DHADDA_DEMO__ = (function () {
  const cats = [
    {id:'food',name:'Food',icon:58763,color:0xFFEF6C00,budget:8000},
    {id:'gym',name:'Gym',icon:0xe1d4,color:0xFFC2185B,budget:2000},
    {id:'transport',name:'Transport',icon:58765,color:0xFF1565C0,budget:3000},
    {id:'rent',name:'Rent',icon:0xe2dc,color:0xFF6A1B9A,budget:15000},
    {id:'other',name:'Other',icon:0xe8b0,color:0xFF009688,budget:0},
  ];
  const projects = [
    {id:'evt-chapakot',name:'Chapakot night out',note:'Weekend trip',created:Date.now()-9*864e5,icon:0xe53a,color:0xFF009688},
    {id:'evt-grocery',name:'Monthly groceries',note:'',created:Date.now()-20*864e5,icon:0xe563,color:0xFFEF6C00},
  ];
  const notes = {
    food:['Momo','Khaja','Lunch','Daal bhat','Chicken','Groceries','Tea','Snacks'],
    gym:['Gym fee','Trainer','Supplements'],
    transport:['Bus','Taxi','Fuel','Metro'],
    rent:['Rent'],
    other:['Utilities','Mobile bill','Medicine'],
  };
  const amounts = {food:[120,250,400,800,60],gym:[500,1000,1500],transport:[50,120,300,600],rent:[12000,15000],other:[200,500,1000]};
  const txns = [];
  const now = new Date();
  for (let m = 2; m >= 0; m--) {
    for (let i = 0; i < 14; i++) {
      const c = i % 2 === 0 ? 'food' : ['gym','transport','rent','other'][i % 4];
      const day = Math.max(1, 28 - i * 2);
      const d = new Date(now.getFullYear(), now.getMonth() - m, day, 9 + (i % 9), 0);
      const arr = amounts[c];
      const val = arr[i % arr.length];
      const projectId = (m === 0 && i < 4) ? 'evt-chapakot' : (m === 1 && i < 3) ? 'evt-grocery' : '';
      txns.push({id:`demo-${m}-${i}`,type:'expense',amount:val,categoryId:c,date:d.getTime(),
        note:notes[c][i % notes[c].length],mode:['cash','bank','card','ewallet'][i % 4],projectId});
    }
    txns.push({id:`demo-inc-${m}`,type:'income',amount:45000,categoryId:'other',
      date:new Date(now.getFullYear(),now.getMonth()-m,1,10).getTime(),note:'Salary',mode:'bank',projectId:''});
  }
  const loans = [
    {id:'loan-samip',person:'Samip',lent:2500,dateLent:now.getTime()-7*864e5,dueDate:now.getTime()+14*864e5,
      note:'Lunch money',repayments:[{id:'r1',amount:500,date:now.getTime()-3*864e5,note:''}],topups:[],kind:'lent',remindAt:0},
    {id:'loan-sita',person:'Sita',lent:5000,dateLent:now.getTime()-40*864e5,dueDate:now.getTime()-5*864e5,
      note:'Rent share',repayments:[{id:'r2',amount:2000,date:now.getTime()-10*864e5,note:'Partial'}],topups:[],kind:'lent',remindAt:0},
    {id:'loan-anish',person:'Anish',lent:1000,dateLent:now.getTime()-12*864e5,dueDate:0,
      note:'',repayments:[],topups:[{id:'t1',amount:500,date:now.getTime()-6*864e5,note:''}],kind:'borrowed',remindAt:0},
  ];
  return {cats,txns,loans,projects,meta:{
    currency:'NPR',themeMode:'system',accent:'#006A60',userName:'Binod',calendarSystem:'ad',hideBalance:false,
    homeLayout:[
      {id:'balance',visible:true},{id:'stats',visible:true},{id:'categories',visible:true},
      {id:'budgets',visible:true},{id:'events',visible:true},{id:'recent',visible:true},
      {id:'todayRing',visible:false},{id:'rhythm',visible:false},{id:'forecast',visible:false},
    ],
  }};
})();

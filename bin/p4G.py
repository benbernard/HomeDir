#!/usr/bin/python

# Script to convert "p4 -G" output to text.
# See the "-h" flag for usage information.
import getopt, marshal, sys, re, time, os

def printer_factory( argv, settings ):
  """Factory used to instantiate correct output strategy class."""
  valfilter = value_filter( settings )
  asv = (argv,settings,valfilter)
  format_mapping = {"single":  (single_line_printer, asv),
		    "multi":   (multi_line_printer,  asv),
		    "keysonly":(keys_printer, (argv, settings)),
		    "key_details":(keys_printer_detailed,(settings, valfilter)),
		    "simple":  (simple_printer, (settings, valfilter))
  }
  klass = format_mapping[settings["format"]]
  return apply(klass[0],klass[1])

def isInt( str ):
  """Utility function: Is the given string an integer?"""
  try: int( str )
  except ValueError: return 0
  else: return 1

class simple_printer:
  """Simple printer: one field per line. """
  def __init__(self, settings, valfilter):
    self.vf = valfilter

  def print_dict(self, num, dict ):
    print '\n--%d--' % num
    for key in dict.keys():
      print "%s: %s" % (key, self.vf.val(dict[key], key))

  def done( self ):
      return None

class keys_printer:
  """Only print the keys observed."""
  def __init__ ( self, argv,  settings ):
    self.aryhndlr = Array_handler()
    self.allkeys = {}
    
  def print_dict( self, num, dict ):
    for k in dict.keys():
      indexes = self.aryhndlr.get_indexes(k)
      if "indexes" in indexes:
	key = indexes["basename"] + ",".join(["N"]*len(indexes["indexes"]))
	self.allkeys[key] = 1
      else:
	self.allkeys[k] = 1

  def done( self ):
    keys= self.allkeys.keys()
    keys.sort()
    for k in keys:
      print k



class keys_printer_detailed:
  """Print the keys observed and give details about indexes and values."""
  def __init__ ( self,  settings, valfilter ):
    self.aryhndlr = Array_handler()
    self.valfilter = valfilter    # Used to filter values
    self.allkeys = {}             # List of keys and details
    self.count = 0                # Sum of records encountered
    # Default limit of values to consider too many to show
    self.max_values = settings["max_unique_values"] 
      
    
  def print_dict( self, num, dict ):
    self.count += 1

    allkeys=self.aryhndlr.arrayize_dict(dict)
    unnumbered_keys = allkeys["keys"]
    # Handle unnumbered keys
    for k in unnumbered_keys:
      if k not in self.allkeys:
	self.allkeys[k] = {"cnt":0,"values":{"text":{}}}
      self.allkeys[k]["cnt"] += 1
      self.record_values(self.allkeys[k]["values"], dict[k])

    #Handle Indexed Keys
    numkeys=allkeys["numkeys"]
    for key in numkeys:
      numkey = numkeys[key]
      k = key + ",".join(["N"]*len(numkey["max"])) # Gen keyname e.g. keyN,N
      curmax = numkey["max"][:]
      curmin = numkey["min"][:]
      if k not in self.allkeys:
	self.allkeys[k] = {"cnt":0,"values":{"text":{}}, "minmax":curmin,"maxmax":curmax}
      keyinfo = self.allkeys[k]
      keyinfo["cnt"] += 1
      keyinfo["maxmax"] = map(max,zip(keyinfo["maxmax"],curmax))
      keyinfo["minmax"] = map(min,zip(keyinfo["minmax"],curmin))
      
      #Record unique values
      if "values" in keyinfo:
	for val in numkey["data"]:
	  self.record_values(keyinfo["values"], val)
	if not len(keyinfo["values"]):
	  del keyinfo["values"]
	
  def record_int_values(self, dict, value):
    if not isInt(value): return
    intvalue = int(value)
    if "int" not in dict:
      dict["int"] = {"min":intvalue,"max":intvalue}
    ints = dict["int"]
    ints["max"] = max(ints["max"],intvalue)
    ints["min"] = min(ints["min"],intvalue)
    return

  def record_values(self, dict, value):
    self.record_int_values(dict,value)
    if "text" not in dict: return
    values = dict["text"]
    if value not in values:
      values[value] = 0
    values[value] += 1
    if len(values) > self.max_values:
      del dict["text"]

  def done( self ):
    keys= self.allkeys.keys()
    keys.sort()
    pad = len(str(self.count))+1
    for k in keys:
      base=self.allkeys[k]
      print  "%*d %s"%(pad, base["cnt"],k),
      if "minmax" in base:
	ranges = zip(base["minmax"],base["maxmax"])
	maxparts = map(self.range_str,ranges)
	print "=(%s)"%(",".join(maxparts)),
      if "values" in base:
	values=""
	if "text" in base["values"]:
	  values = self.fmt_values(base["values"]["text"],pad+len(k))
	elif "int" in base["values"]:
	  range = (base["values"]["int"]["min"],base["values"]["int"]["max"])
	  values = "range: "+ self.range_str(range,self.valfilter)
	print values,
      print
	
    print "%*d Records" % (pad,self.count)

  def fmt_values(self, vals, pad):
    ret = "v:"
    j = " ".join([str(k) for k in vals])
    if len(j) < 65:
      ret += "(%r)"%(vals)
    else:
      cr = "\n%*s"%(pad,"")
      valkeys = vals.keys()
      valkeys.sort()
      for k in valkeys:
	ret += cr + "'%s': %d"%(k,vals[k])
    return ret
      
  def range_str( self, tuple , vf=None):
    low = str(tuple[0])
    hi = str(tuple[1])
    ret = [low]
    if low!=hi:
	ret.append(hi)
    if vf is None:
      return "-".join(ret)
    else:
      return "-".join(map(vf.val,ret))


class format_printer:
  """Base class for classes that print records."""
  def __init__(self, argv, settings, valfilter ):
    self.argv=argv
    self.vf = valfilter
    self.fmt_string = settings["fmt_string"]
    if self.fmt_string == "": 
      self.fmt_string = self.vf.join(("%s",)*len(argv))
    self.aryhndlr = Array_handler(self.vf)
    self.split_dict = settings["split_dict"]
    
  def done( self ):
    return None

class single_line_printer(format_printer):
  """Prints one line per record."""
  def print_dict(self, num, orig_dict):
    alldicts=[orig_dict]
    if self.split_dict:
      alldicts = self.aryhndlr.split_dict(orig_dict)
    
    for dict in alldicts:
      allkeys=self.aryhndlr.arrayize_dict(dict)
      numkeys=allkeys["numkeys"]
      values=[]
      for field in self.argv:
	if numkeys.has_key(field):
	  filtered = [self.vf.val(v,field) for v in numkeys[field]['data']]
	  values.append(self.vf.join(filtered))
	else:
	  if dict.has_key(field) and dict[field] != "":
	    values.append(self.vf.val(dict[field],field))
	  else:
	    values.append(self.vf.get_null())
      print self.fmt_string % tuple(values)
  
class multi_line_printer(format_printer):
  def print_dict(self, num, orig_dict):
    alldicts=[orig_dict]
    if self.split_dict:
      alldicts = self.aryhndlr.split_dict(orig_dict)
    
    for dict in alldicts:
      allkeys=self.aryhndlr.arrayize_dict(dict)
      numkeys=allkeys["numkeys"] 
      key_maxs = [ numkeys[field]['max'][0] for field in self.argv if numkeys.has_key(field) ]
      key_maxs.append(0)
      maxkey = max(key_maxs)
      for item in xrange(maxkey+1):
	values=[]
	for field in self.argv:
	  if field in numkeys:
	    if item < len(numkeys[field]['data']):
	      values.append(self.vf.val(numkeys[field]['data'][item],field))
	    else:
	      values.append(self.vf.get_null())
	  else:
	    if dict.has_key(field) and dict[field] != "":
	      values.append(self.vf.val(dict[field]))
	    else:
	      values.append(self.vf.get_null())
	print self.fmt_string % tuple(values)
  
class Array_handler:
  trailing_digits = re.compile(r'^(.*?)((\d+,)*\d+)$')
  def __init__( self, valfilter=None ):
    self.vf = valfilter
    if self.vf == None: self.vf = value_filter()
    
  def arrayize_dict( self, dict):
    """Create a dictionary of information about numbered keys.
      
	return_value = { "numkeys":
			  { "key_basenameA" : { "data": [ V0, V1, ... ]
					     "keys": [k0, k1, ... ]
					     "min": [min0,min1,...]
					     "max": [max0,max1,...]
					    }
			 "keys": {"keyA":1,"keyB":1,... }
	For multi-indexed keys, V0 = key_basenameA0,0  +  key_basenameA0,1 + ...
	                        V1 = key_basenameA1,0  +  key_basenameA1,1 + ...
    """
    allkeys = self.get_numbered_keys( dict )
    numkeys = allkeys["numkeys"]

    for key in numkeys:
      numkeys[key]['data'] = [] 
      data = numkeys[key]['data']
      keys = numkeys[key]['keys']
      for key in keys:
	if key is None:
	  value = self.vf.get_value(key)
	elif hasattr(key,"startswith"): #is it a string?
	  value = self.vf.get_value(dict[key])
	else: #it's an array
	  value = self.array_value(key)
	data.append(value)
	
    return allkeys

  def array_value(self, arr, ):
    parts = []
    for item in arr:
      if item is None:
	parts.append(self.vf.get_null())
      elif hasattr(item,"startswith"): 
	parts.append(self.vf.get_value(dict[key]))
      else: 
	parts.append(self.array_value(arr))
    ret = "[%s]" %(self.vf.join(parts))
    return ret

  def get_indexes( self, string ):
    """Returns a dict with basename and indexes as keys.
	Dictionary format = { "name": keyname,
			      "basename": keyname-minus-indexes
			      "indexes":[index0,index1]"""

    ret = {"basename":string, "name":string}
    if not string[-1:].isdigit():
      return ret
    m = self.trailing_digits.search( string )
    if not m: 
      raise RuntimeException,"Strings (%s) didn't match trailing_digits"%(string)
    (ret["basename"], nums_with_commas) = m.group(1,2)
    ret["indexes"] = [int(num) for num in nums_with_commas.split(",")]
    return ret

  def get_numbered_keys( self,  dict ):
    """Create a dictionary of numbered keys with index range information.
information
      Dictionary format = {"keys":  { "keyA":1, "keyB":1,.... }
			   "numkeys": { "keybasenameA" = {
					   "min":[min0,min1...],
					   "max":[max0,max1,...]
					   "keys":[keybasenameA0,....   ]
			              } 
			  }
    """
    numkeys={}
    unnumkeys={}
    for key in dict:
      indexes = self.get_indexes( key )
      if indexes.has_key("indexes"):
	self.add_index( numkeys, indexes )
      else:
	unnumkeys[key] = dict[key]
	
    allkeys = { "numkeys":numkeys,"keys":unnumkeys}
    return allkeys

  def add_index( self, numkeys, keyinfo):
    basename = keyinfo["basename"]
    indexes = keyinfo["indexes"]
    if basename not in numkeys:
      numkeys[basename] = {'min':indexes[:],'max':indexes[:],"keys":[]}
    else: 
      funcs = {"min":min,"max":max}
      for key in ("min","max"):
	len_numkeys = len(numkeys[basename][key])
	len_indexes = len(indexes)
	if len_numkeys < len_indexes:
	  numkeys[basename][key] += [None]*(len_indexes-len_numkeys)
	func = funcs[key]
	for n in xrange(len_indexes):
	  index = indexes[n]
	  numkeys[basename][key][n] = func(numkeys[basename][key][n],index)
    data =  numkeys[basename]["keys"]
    len_indexes = len(indexes)
    for idx in xrange(len_indexes):
      index = indexes[idx]
      if len(data) <= index:
	data += [None]*(index-len(data)+1)
      if idx+1 < len_indexes: # Is there another index after this?
	if data[index] is None:
	    data[index] = []
	    data = data[index]
      else: #final index
	data[index] = keyinfo["name"]
  
  def split_dict( self, dict ):
    """ Convert dict with numbered keys into an array of dicts w/unnumbered keys.
    """
    all_keys = self.arrayize_dict( dict )
    num_keys = all_keys["numkeys"] 
    master_nonnum =  all_keys["keys"]
    key_maxs = [ num_keys[field]['max'][0] for field in num_keys ] 
    key_max.append(0) # make sure there is at least one
    maxkey = max (key_maxs)
       
    dict_array = []
    for idx in range( 0, maxkey+1 ):
      dict_array.append({})
      dict_array[idx].update(master_nonnum)
      for key in num_keys:
	if len(num_keys[key]["max"])==1:
	  nkey = "%s%d" % (key, idx)
	  if dict.has_key(nkey):
	    dict_array[idx][key] = dict[nkey]
	else:
	  #BUG: Currently only handles doublly indexed keys
	  for cnt in range( 0, num_keys[key]["max"][1]+1 ): 
	    nkey="%s%d,%d" %(key,idx,cnt)
	    if dict.has_key(nkey):
	      dict_array[idx]["%s%d"%(key,cnt)] = dict[nkey]
  
    return dict_array

class value_filter:
  """Class to filter strings, such as for ints to datetime."""
  def __init__( self, settings=None ):
    if settings == None:
	settings = { "null_str":"", "separator":" ", "empty_str":""}
    self.time_start = 100000
    self.null = settings["null_str"]
    self.empty = settings["empty_str"]
    self.sep = settings["separator"]

  def val( self, str, key=None):
    """Used to format values for printing."""
    # Handle Integers as Unix Epoch time.
    i = None
    if isInt( str ):
      i = int( str )
      if i > 1000000:
	return ("%d (%s)"%(i, time.asctime( time.localtime( i))))
    return(str)

  def get_value( self, value):
      if value is None:
	return self.get_null()
      elif value == "":
	return self.get_empty()
      return value
  def get_null( self ): return (self.null)
  def get_empty( self ): return (self.empty)
  def join( self, arg ):
    """Join using the default separator."""
    ret=""
    try:
      ret= self.sep.join(arg)
    except TypeError, e:
      ret= self.sep.join([str(item) for item in arg])
    return ret



def usage( message ):
  """Provides usage message."""
  pn = os.path.basename(sys.argv[0])
  print """%s
USAGE:  p4 -G p4cmd [opts] | %s [-f fmt_string] [-m|-S] [-k|-K] [-n nullstr] [fieldname ...]
  -f fmt_string   A printf-like fmt string (only %%s) for formatting fields.
	          Must contains same number of %%s as fields listed.
  -m              How to print number fields, use one line per instance.
  -K		  Just list keys found, numbered keys listing common values.
  -k		  Just list keys found, numbered keys.
  -S              Split the dictionary into multiple ones. (Useful for filelog)
  -s sep          Default separator to use between words (Default: space)
  -n nullstr      String to use when a field is empty.
  Fields should be the name of fields listed in the p4cmd output.
""" % (message, pn) 
  sys.exit(1)


def get_settings( argv ):
  try:
    (opts,args) = getopt.getopt(argv[1:], "mf:n:kKSs:")
  except getopt.GetoptError, excep:
    usage("%s" % excep)
  options={}
  for opt, value in opts:
    if options.has_key(opt):
      if type(options[opt]) == type([]):
	options[opt].append(value)
      else:
        options[opt]=[options[opt], value]
    else:
      options[opt]=value

  settings = {}
  # Determin format to use
  settings["format"]="simple"
  if options.has_key("-m"):
    settings["format"]="multi"
  elif options.has_key("-k"):
    settings["format"]="keysonly"
  elif options.has_key("-K"):
    settings["format"]="key_details"
  elif len(args) != 0:
    settings["format"]="single"

  # format string
  settings["fmt_string"]=""
  if options.has_key("-f"):
    settings["fmt_string"]=options["-f"]

  #String to use for NULL values
  settings["null_str"] = ""
  settings["empty_str"] = ""
  if options.has_key("-n"):
    settings["null_str"] = options["-n"]
  #String separator
  settings["separator"] = " "
  if options.has_key("-s"):
    settings["separator"] = options["-s"]

  #Dictionary spliting options
  settings["split_dict"]=0
  if options.has_key("-S"):
    settings["split_dict"] = 1

  #Reporting values
  settings["max_unique_values"] = 10

  return (args, settings)
  
def main(argv):
  (args, settings) = get_settings(argv)
  return main_loop( args, settings )

def main_loop( args, settings ):
  """ Basic read loop of STDIN, and calls print classes."""
  print_class = printer_factory( args, settings )
  try:
    num=0
    while 1:
      dict = marshal.load(sys.stdin)
      num  = num+1
      print_class.print_dict(num, dict)
  except EOFError: return print_class.done()
  except ValueError, v:
	if num == 0 and v.args[0] == "bad marshal data":
	    print "Are you using 'p4 -G' as input? Input has bad marshal data."
	    return 2
	else: raise

if __name__ == '__main__':
  try:
    sys.exit(main(sys.argv))
  except KeyboardInterrupt:
    sys.exit(2)

import ClientServer::*;
import GetPut::*;
import FIFO::*;
import FIFOF::*;
import Assert::*;

typeclass ToClientServer#(type fifo1, type fifo2, type req_type, type resp_type);
   function Client#(req_type, resp_type) toClient(fifo1 reqQ, fifo2 respQ);
   function Server#(req_type, resp_type) toServer(fifo1 reqQ, fifo2 respQ);
endtypeclass

instance ToClientServer#(FIFO#(req_type), FIFO#(resp_type), req_type, resp_type);
   function Client#(req_type, resp_type) toClient(FIFO#(req_type) reqQ, FIFO#(resp_type) respQ);
      return (interface Client#(req_type, resp_type);
                 interface Get request = toGet(reqQ);
                 interface Put response = toPut(respQ);
              endinterface);
   endfunction

   function Server#(req_type, resp_type) toServer(FIFO#(req_type) reqQ, FIFO#(resp_type) respQ);
      return (interface Server#(req_type, resp_type);
                 interface Put request = toPut(reqQ);
                 interface Get response = toGet(respQ);
              endinterface);
   endfunction
endinstance

instance ToClientServer#(FIFOF#(req_type), FIFOF#(resp_type), req_type, resp_type);
   function Client#(req_type, resp_type) toClient(FIFOF#(req_type) reqQ, FIFOF#(resp_type) respQ);
      return (interface Client#(req_type, resp_type);
                 interface Get request = toGet(reqQ);
                 interface Put response = toPut(respQ);
         endinterface);
   endfunction

   function Server#(req_type, resp_type) toServer(FIFOF#(req_type) reqQ, FIFOF#(resp_type) respQ);
      return (interface Server#(req_type, resp_type);
                 interface Put request = toPut(reqQ);
                 interface Get response = toGet(respQ);
         endinterface);
   endfunction
endinstance

module mkEmptyClient(Client#(req_type, resp_type));
   interface Get request;
      method ActionValue#(req_type) get() if (False);
         return ?;
      endmethod
   endinterface
   interface Put response;
      method Action put(resp_type resp);
         dynamicAssert(True, "(%m) Empty Client should never expect any response data");
      endmethod
   endinterface
endmodule

module mkEmptyServer(Server#(req_type, resp_type));
   interface Put request;
      method Action put(req_type);
         dynamicAssert(True, "(%m) Empty Server should never expect any request data");
      endmethod
   endinterface
   interface Get response;
         method ActionValue#(resp_type) get() if (False);
         return ?;
      endmethod
   endinterface
endmodule

#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
#Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
Capslock::ScrollLock

class Config
{
   static sHost := "10.3.1.2"
   static iPort := 666
   static iSleep := 200

   static DEBUG := 0
   static WSAVersion := (2<<8) | 2 ; version 2.2
}

class SizeOf
{
   static sockaddr_in := 16
   static addrinfo := A_Is64bitOS ? 48  : 32
   static WSADATA  := A_Is64bitOS ? 400 : 396
}

class Offset
{
   class addrinfo
   {
      static ai_flags     := 0
      static ai_family    := 4
      static ai_socktype  := 8
      static ai_protocol  := 12
      static ai_addrlen   := 16
      static ai_canonname := A_Is64bitOS ? 24 : 20
      static ai_addr      := A_Is64bitOS ? 32 : 24
      static ai_next      := A_Is64bitOS ? 40 : 28
   }
   
   class sockaddr_in
   {
      static sin_family := 0
      static sin_port   := 2
      static in_addr    := 4
      static sin_zero   := 8
   }
}

class Const
{
   static AF_INET := 2

   static SOCK_STREAM := 1

   static IPPROTO_TCP := 6

   static FORMAT_MESSAGE_FROM_SYSTEM    := 0x1000
   static FORMAT_MESSAGE_IGNORE_INSERTS := 0x200
}

VarDump(ByRef pVar, iLen)
{
   sDump := ""
   iIter := 0
   while (iIter < iLen)
   {
      sDump := sDump . Format(" {:02x}", NumGet(pVar + 0, iIter, "UChar"))
      iIter++
   }
   return SubStr(sDump, 1)
}

StrJoin(ByRef aStr, sSep)
{
   sResult := ""
   For _, sVal in aStr
      sResult := sResult . ", " . sVal
   return SubStr(sResult, 2)
}

DllCallCheck(aParams*)
{
   iResult := DllCall(aParams*)
   if (ErrorLevel != 0)
   {
      MsgBox % Format("Invocation({:}) failed with ErrorLevel({:})", StrJoin(aParams, ", "), ErrorLevel)
   }
   else if (Config.DEBUG)
   {
      MsgBox % Format("Invocation({:}) returned({:})", StrJoin(aParams, ", "), iResult)
   }
   return iResult
}

GetError(iErrorId:=-1)
{
   VarSetCapacity(sMessage, 1024, 0)

   if (iErrorId == -1)
      iErrorId := DllCallCheck("Ws2_32\WSAGetLastError")

   iFlags := Const.FORMAT_MESSAGE_FROM_SYSTEM | Const.FORMAT_MESSAGE_IGNORE_INSERTS
   iResult := DllCallCheck("FormatMessage"
                    ,"UInt", iFlags      ; dwFlags
                    ,"UInt", 0           ; lpSource
                    ,"UInt", iErrorId    ; dwMessageID
                    ,"UInt", 0           ; dwLanguageID
                    ,"Ptr", &sMessage    ; lpBuffer
                    ,"UInt", 1024        ; nSize
                    ,"Ptr", 0)           ; Arguments

   if (iResult == 0)
      return iErrorId
   
   return sMessage
}

CleanExit(iStatus, pAddrinfo:=-1, iSocket:=-1)
{
   if (iSocket >= 0)
      DllCallCheck("Ws2_32\closesocket", "UInt", iSocket)
   if (pAddrinfo >= 0)
      DllCallCheck("Ws2_32\freeaddrinfo", "Ptr", pAddrinfo)
   DllCallCheck("Ws2_32\WSACleanup")

   Exit, iStatus
}

WSAStartup()
{
   VarSetCapacity(wsaData, SizeOf.WSADATA)
   iResult := DllCallCheck("Ws2_32\WSAStartup", "UShort", Config.WSAVersion, "Ptr", &wsaData)

   if (iResult != 0)
   {
      MsgBox % Format("WSAStartup failed with error: {:}", GetError())
      CleanExit(2)
   }

   return iResult
}

ResolveName(ByRef sHost, iPort)
{
   sPort := Format("{:d}", iPort)

   VarSetCapacity(aiHints, SizeOf.addrinfo, 0)
   NumPut(Const.AF_INET,     aiHints, Offset.ai_family)
   NumPut(Const.SOCK_STREAM, aiHints, Offset.ai_socktype)
   NumPut(Const.IPPROTO_TCP, aiHints, Offset.ai_protocol)

   VarSetCapacity(ppAddrinfo, A_PtrSize, 0)
   result := DllCallCheck("Ws2_32\GetAddrInfo"
                    ,"UPtr", &sHost       ; pNodeName
                    ,"UPtr", &sPort       ; pServiceName
                    ,"UPtr", &aiHints     ; pHints
                    ,"UPtr", &ppAddrinfo) ; pResult

   pAddrinfo := NumGet(ppAddrinfo, 0, "UPtr")

   if (result != 0)
   {
      MsgBox % Format("Can't resolve name({:}) with error: {:}", host, GetError())
      CleanExit(1, pAddrinfo)
   }

   return pAddrinfo
}

CreateSocket(pAddrinfo)
{
   iFamily   := NumGet(pAddrinfo + 0, Offset.addrinfo.ai_family)
   iSockType := NumGet(pAddrinfo + 0, Offset.addrinfo.ai_socktype)
   iProtocol := NumGet(pAddrinfo + 0, Offset.addrinfo.ai_protocol)
 
   iSocket := DllCallCheck("Ws2_32\socket", "Int", iFamily, "Int", iSockType, "Int", iProtocol)
   if (iSocket < 0)
   {
      MsgBox % Format("Can't create socket with family({:}), type({:}), protocol({:}): {:}", iFamily, iSockType, iProtocol, GetError())
   }

   return iSocket
}

Connect(iSocket, pAddrinfo)
{
   pSockaddr    := NumGet(pAddrinfo + 0, Offset.addrinfo.ai_addr)
   iSockaddrLen := NumGet(pAddrinfo + 0, Offset.addrinfo.ai_addrlen)

   iResult := DllCallCheck("Ws2_32\connect", "UInt", iSocket, "Ptr", pSockaddr, "UInt", iSockaddrLen)
   if (iResult < 0)
   {
      iPort_net  := NumGet(pSockaddr + 0, Offset.sockaddr_in.sin_port, "UShort")
      iPort_host := DllCallCheck("Ws2_32\ntohs", "UShort", iPort_net)

      iAddr := NumGet(pSockaddr + 0, 4)
      sAddr := DllCallCheck("Ws2_32\inet_ntoa", "UInt", iAddr, "Str")
      MsgBox % Format("Can't connect to host({:}) on port({:d}): {:}", sAddr, iPort_host, GetError())
   }

   return iResult
}

Main()
{
   Sleep, Config.iSleep
   WSAStartup()

   pAddrinfo := ResolveName(Config.sHost, Config.iPort)
   pIter := pAddrinfo
   iSocket := -1

   while (pIter != 0) {
      iSocket := CreateSocket(pIter)
      if (iSocket >= 0)
      {
         if (Connect(iSocket, pIter) >= 0)
            break
         else
            DllCallCheck("Ws2_32\closesocket", "UInt", iSocket)
      }

      pIter := NumGet(pIter + 0, Offset.addrinfo.ai_next, "UPtr")
   }

   if (pIter == 0)
   {
      MsgBox % Format("Could not connect to any host: {:}", GetError())
      CleanExit(3, pAddrinfo)
   }

   CleanExit(0, pAddrinfo, iSocket)
}

!`::
   Main()
